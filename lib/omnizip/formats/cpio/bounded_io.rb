# frozen_string_literal: true

module Omnizip
  module Formats
    module Cpio
      # IO wrapper that limits reading to a specific byte count
      #
      # Used to read file content from CPIO archives where the file size
      # is known in advance but the underlying IO stream continues.
      class BoundedIO
        attr_reader :length, :remaining

        # Initialize bounded IO
        #
        # @param io [IO] Underlying IO stream
        # @param length [Integer] Maximum bytes to read
        # @yield Block called when EOF is reached (for reading padding)
        def initialize(io, length, &eof_callback)
          @io = io
          @length = length
          @remaining = length
          @eof_callback = eof_callback
          @eof = false
        end

        # Read bytes from the IO
        #
        # @param size [Integer, nil] Number of bytes to read (nil = remaining)
        # @return [String, nil] Data read or nil at EOF
        def read(size = nil)
          return nil if eof?

          size = @remaining if size.nil?
          data = @io.read(size)
          return nil if data.nil?

          @remaining -= data.bytesize
          eof?
          data
        end

        # System read (raises on EOF)
        #
        # @param size [Integer] Number of bytes to read
        # @return [String] Data read
        # @raise [EOFError] If at end of bounded region
        def sysread(size)
          raise EOFError, "end of file reached" if eof?

          read(size)
        end

        # Check if at end of bounded region
        #
        # @return [Boolean] True if no more bytes to read
        def eof?
          return false if @remaining.positive?
          return @eof if @eof

          @eof_callback&.call
          @eof = true
        end
      end
    end
  end
end
