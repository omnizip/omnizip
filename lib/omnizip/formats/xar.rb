# frozen_string_literal: true

require_relative "xar/constants"
require_relative "xar/header"
require_relative "xar/entry"
require_relative "xar/toc"
require_relative "xar/reader"
require_relative "xar/writer"

module Omnizip
  module Formats
    # XAR archive format support
    #
    # XAR (eXtensible ARchive) format is primarily used on macOS for:
    # - Software packages (.pkg files)
    # - OS installers
    # - Software distribution
    #
    # Features:
    # - GZIP-compressed XML Table of Contents (TOC)
    # - Multiple compression algorithms (gzip, bzip2, lzma, xz, none)
    # - Checksum verification (MD5, SHA1, SHA256, etc.)
    # - Extended attributes (xattrs)
    # - Hardlinks and symlinks
    # - Device nodes and FIFOs
    #
    # @example Create XAR archive
    #   Omnizip::Formats::Xar.create('archive.xar') do |xar|
    #     xar.add_file('document.pdf')
    #     xar.add_directory('resources/')
    #   end
    #
    # @example Extract XAR archive
    #   Omnizip::Formats::Xar.extract('archive.xar', 'output/')
    #
    # @example List XAR contents
    #   entries = Omnizip::Formats::Xar.list('archive.xar')
    #   entries.each { |e| puts "#{e.name} (#{e.size} bytes)" }
    module Xar
      # Re-export constants for external access
      CKSUM_NONE = Constants::CKSUM_NONE
      CKSUM_SHA1 = Constants::CKSUM_SHA1
      CKSUM_MD5 = Constants::CKSUM_MD5
      CKSUM_OTHER = Constants::CKSUM_OTHER

      class << self
        # Create XAR archive
        #
        # @param path [String] Output XAR file path
        # @param options [Hash] Archive options
        # @option options [String] :compression Compression algorithm (gzip, bzip2, lzma, xz, none)
        # @option options [Integer] :compression_level Compression level (1-9)
        # @option options [String] :toc_checksum TOC checksum algorithm (sha1, md5, sha256)
        # @option options [String] :file_checksum File checksum algorithm (sha1, md5, sha256)
        # @yield [writer] Block for adding files/directories
        # @yieldparam writer [Writer] XAR writer
        # @return [String] Path to created archive
        #
        # @example Create archive with gzip compression
        #   Omnizip::Formats::Xar.create('archive.xar', compression: 'gzip') do |xar|
        #     xar.add_file('config.yml')
        #     xar.add_directory('config.d/')
        #   end
        #
        # @example Create archive with bzip2 and SHA256 checksums
        #   Omnizip::Formats::Xar.create('archive.xar',
        #     compression: 'bzip2',
        #     toc_checksum: 'sha256',
        #     file_checksum: 'sha256'
        #   ) do |xar|
        #     xar.add_file('data.bin')
        #   end
        def create(path, options = {})
          Writer.create(path, options) do |writer|
            yield writer if block_given?
          end
        end

        # Open XAR archive for reading
        #
        # @param path [String] Path to XAR file
        # @yield [reader] Block for reading archive
        # @yieldparam reader [Reader] XAR reader
        # @return [Reader] XAR reader
        #
        # @example Read XAR archive
        #   Omnizip::Formats::Xar.open('archive.xar') do |xar|
        #     xar.entries.each { |entry| puts entry.name }
        #   end
        def open(path)
          reader = Reader.open(path)

          if block_given?
            begin
              yield reader
            ensure
              reader.close
            end
          else
            reader
          end
        end

        # List XAR archive contents
        #
        # @param path [String] Path to XAR file
        # @return [Array<Entry>] Archive entries
        #
        # @example List archive contents
        #   entries = Omnizip::Formats::Xar.list('archive.xar')
        #   entries.each { |e| puts "#{e.name} (#{e.size} bytes)" }
        def list(path)
          open(path, &:entries) # rubocop:disable Security/Open
        end

        # Extract XAR archive
        #
        # @param xar_path [String] Path to XAR file
        # @param output_dir [String] Output directory
        #
        # @example Extract archive
        #   Omnizip::Formats::Xar.extract('archive.xar', 'output/')
        def extract(xar_path, output_dir)
          open(xar_path) do |xar| # rubocop:disable Security/Open
            xar.extract_all(output_dir)
          end
        end

        # Get archive information
        #
        # @param path [String] Path to XAR file
        # @return [Hash] Archive information
        #
        # @example Get archive info
        #   info = Omnizip::Formats::Xar.info('archive.xar')
        #   puts "Format: XAR version #{info[:header][:version]}"
        #   puts "Files: #{info[:file_count]}"
        def info(path)
          open(path, &:info) # rubocop:disable Security/Open
        end

        # Auto-register XAR format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".xar", Reader)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Xar.register!
