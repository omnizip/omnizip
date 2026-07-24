# frozen_string_literal: true

require "tempfile"

module Omnizip
  module Temp
    # RAII-pattern temporary file with automatic cleanup
    class TempFile
      attr_reader :path

      # Create new temporary file
      # @param prefix [String] Filename prefix
      # @param suffix [String] Filename suffix
      # @param directory [String, nil] Directory (nil = system default)
      def initialize(prefix: "omniz_", suffix: "", directory: nil)
        @prefix = prefix
        @suffix = suffix
        @directory = directory
        @tempfile = nil
        @path = nil
        @kept = false
        @finalized = false

        create
        setup_finalizer
      end

      # Get the underlying Tempfile object
      # @return [Tempfile] The tempfile
      def file
        @tempfile
      end

      # Write data to temp file
      # @param data [String] Data to write
      # @return [Integer] Bytes written
      def write(data)
        @tempfile.write(data)
      end

      # Read data from temp file
      # @param length [Integer, nil] Number of bytes to read
      # @return [String, nil] Data read
      def read(length = nil)
        @tempfile.read(length)
      end

      # Rewind to beginning of file
      def rewind
        @tempfile.rewind
      end

      # Close the temp file
      def close
        @tempfile.close if @tempfile && !@tempfile.closed?
      end

      # Delete the temp file
      def unlink
        return if @finalized || @kept

        if @tempfile
          @tempfile.close unless @tempfile.closed?
          @tempfile.unlink
          @finalized = true
        end
      rescue StandardError
        # Ignore errors during cleanup
        nil
      end

      # Prevent automatic deletion
      def keep!
        @kept = true
      end

      # Check if file will be kept
      # @return [Boolean] True if file won't be auto-deleted
      def kept?
        @kept
      end

      # Check if file has been finalized
      # @return [Boolean] True if finalized
      def finalized?
        @finalized
      end

      private

      def create
        @tempfile = if @directory
                      ::Tempfile.new(
                        [@prefix, @suffix],
                        @directory,
                        binmode: true,
                      )
                    else
                      ::Tempfile.new(
                        [@prefix, @suffix],
                        binmode: true,
                      )
                    end
        @path = @tempfile.path
      end

      def setup_finalizer
        ObjectSpace.define_finalizer(self, self.class.finalizer(@tempfile))
      end

      # rubocop:disable Lint/IneffectiveAccessModifier
      def self.finalizer(tempfile)
        proc do
          tempfile.close unless tempfile.closed?
          tempfile.unlink
        rescue StandardError
          # Ignore errors in finalizer
          nil
        end
      end
      # rubocop:enable Lint/IneffectiveAccessModifier
    end
  end
end
