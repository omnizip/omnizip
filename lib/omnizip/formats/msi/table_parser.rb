# frozen_string_literal: true

module Omnizip
  module Formats
    module Msi
      # MSI Table Parser
      #
      # Parses MSI database tables from OLE streams. MSI uses a column-major
      # storage format where each column's data is stored contiguously.
      #
      # Key tables for file extraction:
      # - File: File entries with name, size, component, sequence
      # - Component: Links files to directories
      # - Directory: Directory hierarchy
      # - Media: Cabinet file references
      class TableParser
        include Omnizip::Formats::Msi::Constants

        # @return [StringPool] String pool for string lookups
        attr_reader :string_pool

        # @return [Hash] Parsed tables (table_name => rows)
        attr_reader :tables

        # @return [Hash] Column definitions (table_name => columns)
        attr_reader :columns

        # @return [Array<String>] Table names
        attr_reader :table_names

        # @return [Proc] Stream reader method
        attr_reader :read_stream

        # Initialize table parser
        #
        # @param string_pool [StringPool] String pool for lookups
        # @param stream_reader [Proc] Method to read streams
        def initialize(string_pool, stream_reader)
          @string_pool = string_pool
          @read_stream = stream_reader
          @tables = {}
          @columns = {}
          @table_names = []
          load_table_list
          load_column_defs
        end

        # Get table rows
        #
        # @param table_name [String] Table name
        # @return [Array<Hash>] Table rows (each row is a hash of column => value)
        def table(table_name)
          return @tables[table_name] if @tables.key?(table_name)

          @tables[table_name] = parse_table(table_name)
        end

        # Get column definitions for table
        #
        # @param table_name [String] Table name
        # @return [Array<Hash>] Column definitions
        def column_defs(table_name)
          @columns[table_name] || []
        end

        # Check if table exists
        #
        # @param table_name [String] Table name
        # @return [Boolean]
        def table_exists?(table_name)
          @table_names.include?(table_name)
        end

        private

        # Load list of table names from _Tables stream
        def load_table_list
          data = @read_stream.call(TABLES_STREAM)
          return if data.nil? || data.empty?

          # _Tables format: column-major with one column (Table string index)
          # First 2 bytes appear to be header (skip)
          # Then 2-byte string indices for each table name
          return if data.bytesize < 4

          # Skip first 2 bytes (header), read string indices
          offset = 2
          while offset + 2 <= data.bytesize
            str_idx = data[offset, 2].unpack1("v")
            name = @string_pool[str_idx]
            @table_names << name if name
            offset += 2
          end
        end

        # Load column definitions from _Columns stream
        def load_column_defs
          data = @read_stream.call(COLUMNS_STREAM)
          return if data.nil? || data.empty?

          # _Columns format: column-major with 4 columns
          # Column 1: Table (string index, 2 bytes)
          # Column 2: Number (signed short, 2 bytes)
          # Column 3: Name (string index, 2 bytes)
          # Column 4: Type (unsigned short, 2 bytes)

          # Determine number of rows
          num_rows = data.bytesize / 8 # 4 columns * 2 bytes each

          # Extract each column (column-major order)
          col_size = num_rows * 2

          table_col = data[0, col_size].unpack("v*")
          number_col = data[col_size, col_size].unpack("v*")
          name_col = data[col_size * 2, col_size].unpack("v*")
          type_col = data[col_size * 3, col_size].unpack("v*")

          # Build column definitions per table
          num_rows.times do |i|
            table_name = @string_pool[table_col[i]]
            next unless table_name

            col_name = @string_pool[name_col[i]]
            next unless col_name

            # Number column: signed short with nullable bit
            raw_num = number_col[i]
            col_num = raw_num & 0x7FFF
            is_primary_key = raw_num.anybits?(0x8000)

            # Type column: determine storage width
            type_val = type_col[i]
            col_type = parse_column_type(type_val)

            @columns[table_name] ||= []
            @columns[table_name] << {
              name: col_name,
              number: col_num,
              type: col_type[:type],
              width: col_type[:width],
              nullable: col_type[:nullable],
              primary_key: is_primary_key,
            }
          end

          # Sort columns by number for each table
          @columns.each_value do |cols|
            cols.sort_by! { |c| c[:number] }
          end
        end

        # Parse column type from raw type value
        #
        # Type encoding:
        # - Low byte: length or type code
        # - High byte: type category with nullable bit
        #
        # @param raw [Integer] Raw type value
        # @return [Hash] Parsed type info
        def parse_column_type(raw)
          low_byte = raw & 0xFF
          high_byte = (raw >> 8) & 0xFF
          nullable = high_byte.anybits?(0x80)
          type_id = high_byte & 0x7F

          # Determine type and width based on type_id
          # Type 1 = int, Type >= 0x10 = string
          if type_id == 1
            # Integer type
            if low_byte == 2
              { type: :i2, width: 2, nullable: nullable }
            else
              { type: :i4, width: 4, nullable: nullable }
            end
          elsif type_id == 2
            # Long integer
            { type: :i4, width: 4, nullable: nullable }
          elsif type_id >= 0x10
            # String type - width is always 2 (string pool index)
            { type: :string, width: 2, nullable: nullable }
          else
            # Default to string
            { type: :string, width: 2, nullable: nullable }
          end
        end

        # Parse a table stream into rows
        #
        # @param table_name [String] Table name
        # @return [Array<Hash>] Parsed rows
        def parse_table(table_name)
          rows = []
          data = @read_stream.call(table_name)
          return rows if data.nil? || data.empty?

          column_defs = @columns[table_name]
          return rows if column_defs.nil? || column_defs.empty?

          # Calculate row count from data size and column widths
          total_width = column_defs.sum { |c| c[:width] }
          return rows if total_width.zero?

          num_rows = data.bytesize / total_width

          # Parse column by column (column-major order)
          offset = 0
          rows = Array.new(num_rows) { {} }

          column_defs.each do |col|
            num_rows.times do |row_idx|
              value = read_column_value(data, offset, col)
              rows[row_idx][col[:name]] = value
              offset += col[:width]
            end
          end

          rows
        end

        # Read a single column value from data
        #
        # @param data [String] Raw table data
        # @param offset [Integer] Current offset
        # @param col [Hash] Column definition
        # @return [Object] Parsed value
        def read_column_value(data, offset, col)
          case col[:type]
          when :string
            str_idx = data[offset, 2]&.unpack1("v") || 0
            @string_pool[str_idx]
          when :i2
            val = data[offset, 2]&.unpack1("v") || 0
            # Handle nullable marker
            col[:nullable] ? (val & 0x7FFF) : val
          when :i4
            val = data[offset, 4]&.unpack1("V") || 0
            # Handle nullable marker (high bit)
            col[:nullable] ? (val & 0x7FFFFFFF) : val
          end
        end
      end
    end
  end
end
