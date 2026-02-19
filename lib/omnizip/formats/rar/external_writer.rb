# frozen_string_literal: true

require "open3"
require "fileutils"
require_relative "license_validator"

module Omnizip
  module Formats
    module Rar
      # External RAR writer using licensed WinRAR installation
      #
      # This class provides RAR archive creation by wrapping the user's
      # licensed WinRAR command-line tool. It does NOT implement RAR
      # compression internally due to proprietary licensing restrictions.
      #
      # @example Create a RAR archive
      #   writer = ExternalWriter.new('archive.rar')
      #   writer.add_file('document.pdf')
      #   writer.add_directory('photos/')
      #   writer.write
      #
      # @example Create with options
      #   writer = ExternalWriter.new('archive.rar',
      #     compression: :best,
      #     solid: true,
      #     recovery: 5
      #   )
      class ExternalWriter
        # @return [String] Output archive path
        attr_reader :output_path

        # @return [Hash] Compression options
        attr_reader :options

        # @return [Array<String>] Files to add
        attr_reader :files

        # Check if RAR creation is available
        #
        # @return [Boolean] true if WinRAR executable found
        def self.available?
          !find_rar_executable.nil?
        end

        # Get RAR executable information
        #
        # @return [Hash] Executable path and version
        def self.info
          exe = find_rar_executable
          return { available: false } unless exe

          version_output, = Open3.capture2e(exe)
          version = version_output.match(/RAR\s+([\d.]+)/i)&.[](1) || "unknown"

          {
            available: true,
            executable: exe,
            version: version,
          }
        end

        # Find RAR executable on system
        #
        # @return [String, nil] Path to executable or nil
        def self.find_rar_executable
          if RUBY_PLATFORM.match?(/win32|mingw/)
            find_windows_rar
          else
            find_unix_rar
          end
        end

        # Initialize RAR writer
        #
        # @param output_path [String] Output RAR file path
        # @param options [Hash] Compression options
        # @option options [Symbol] :compression Compression level
        #   (:store, :fastest, :fast, :normal, :good, :best)
        # @option options [Boolean] :solid Create solid archive
        # @option options [Integer] :recovery Recovery record percentage (0-10)
        # @option options [Boolean] :encrypt_headers Encrypt file names
        # @option options [String] :password Archive password
        # @option options [Integer] :volume_size Split into volumes (bytes)
        # @option options [Boolean] :test_after_create Test archive after creation
        # @option options [Boolean] :license_confirmed Skip license confirmation
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = default_options.merge(options)
          @files = []
          @directories = []

          validate_availability!
          validate_license! unless @options[:license_confirmed]
        end

        # Add file to archive
        #
        # @param file_path [String] Path to file
        # @param archive_path [String, nil] Path within archive
        # @raise [ArgumentError] if file does not exist
        def add_file(file_path, archive_path = nil)
          raise ArgumentError, "File not found: #{file_path}" unless
            File.exist?(file_path)

          @files << {
            source: File.expand_path(file_path),
            archive_path: archive_path,
          }
        end

        # Add directory to archive
        #
        # @param dir_path [String] Path to directory
        # @param recursive [Boolean] Include subdirectories
        # @param archive_path [String, nil] Path within archive
        # @raise [ArgumentError] if directory does not exist
        def add_directory(dir_path, recursive: true, archive_path: nil)
          raise ArgumentError, "Directory not found: #{dir_path}" unless
            Dir.exist?(dir_path)

          @directories << {
            source: File.expand_path(dir_path),
            recursive: recursive,
            archive_path: archive_path,
          }
        end

        # Create RAR archive
        #
        # @raise [RarNotAvailableError] if WinRAR not available
        # @raise [RuntimeError] if archive creation fails
        def write
          raise RarNotAvailableError unless self.class.available?

          # Build command
          cmd = build_command

          # Execute RAR
          stdout, stderr, status = Open3.capture3(*cmd)

          unless status.success?
            raise "RAR creation failed: #{stderr}\n#{stdout}"
          end

          # Test archive if requested
          test_archive if @options[:test_after_create]

          @output_path
        end

        private

        # Default compression options
        #
        # @return [Hash] Default options
        def default_options
          {
            compression: :normal,
            solid: false,
            recovery: 0,
            encrypt_headers: false,
            password: nil,
            volume_size: nil,
            test_after_create: false,
            license_confirmed: false,
          }
        end

        # Validate WinRAR availability
        #
        # @raise [RarNotAvailableError] if not available
        def validate_availability!
          raise RarNotAvailableError unless self.class.available?
        end

        # Validate license ownership
        #
        # @raise [NotLicensedError] if license not confirmed
        def validate_license!
          return if LicenseValidator.license_confirmed?

          return if LicenseValidator.confirm_license!

          raise NotLicensedError
        end

        # Build RAR command line
        #
        # @return [Array<String>] Command and arguments
        def build_command
          cmd = [rar_executable]

          # Command: a = add
          cmd << "a"

          # Compression method
          cmd << compression_switch

          # Solid archive
          cmd << "-s" if @options[:solid]

          # Recovery record
          cmd << "-rr#{@options[:recovery]}%" if @options[:recovery].positive?

          # Password
          if @options[:password]
            cmd << "-p#{@options[:password]}"
            cmd << "-hp" if @options[:encrypt_headers]
          end

          # Volume size
          cmd << "-v#{@options[:volume_size]}b" if @options[:volume_size]

          # Overwrite existing
          cmd << "-o+"

          # Output archive path
          cmd << @output_path

          # Add files and directories
          @files.each do |file_info|
            cmd << if file_info[:archive_path]
                     # RAR doesn't support renaming in command line easily
                     # Would need to use temporary directory structure
                   end
            file_info[:source]
          end

          @directories.each do |dir_info|
            cmd << "-r" if dir_info[:recursive]
            cmd << "#{dir_info[:source]}/*"
          end

          cmd
        end

        # Get compression switch for level
        #
        # @return [String] Compression switch
        def compression_switch
          case @options[:compression]
          when :store then "-m0"
          when :fastest then "-m1"
          when :fast then "-m2"
          when :normal then "-m3"
          when :good then "-m4"
          when :best then "-m5"
          else "-m3"
          end
        end

        # Test archive integrity
        #
        # @raise [RuntimeError] if test fails
        def test_archive
          cmd = [rar_executable, "t", @output_path]
          stdout, stderr, status = Open3.capture3(*cmd)

          return if status.success?

          raise "Archive test failed: #{stderr}\n#{stdout}"
        end

        # Get RAR executable path
        #
        # @return [String] Path to executable
        def rar_executable
          self.class.find_rar_executable
        end

        # Find WinRAR on Windows
        #
        # @return [String, nil] Path or nil
        def self.find_windows_rar
          # Check common installation paths
          paths = [
            "C:\\Program Files\\WinRAR\\Rar.exe",
            "C:\\Program Files (x86)\\WinRAR\\Rar.exe",
          ]

          # Check PATH
          path_rar = which("rar.exe") || which("Rar.exe")
          paths.unshift(path_rar) if path_rar

          paths.find { |path| File.exist?(path) }
        end

        # Find RAR on Unix systems
        #
        # @return [String, nil] Path or nil
        def self.find_unix_rar
          which("rar")
        end

        # Find executable in PATH
        #
        # @param cmd [String] Command name
        # @return [String, nil] Path or nil
        def self.which(cmd)
          exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
          ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
            exts.each do |ext|
              exe = File.join(path, "#{cmd}#{ext}")
              return exe if File.executable?(exe) && !File.directory?(exe)
            end
          end
          nil
        end
      end
    end
  end
end
