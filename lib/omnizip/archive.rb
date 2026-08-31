# frozen_string_literal: true

module Omnizip
  # High-level block-style archive facade over the registered
  # ArchiveHandlers. This is the API the guides document:
  #
  #   Omnizip::Archive.create('backup.7z', format: :seven_zip,
  #                           level: 9) do |archive|
  #     archive.add_file('report.pdf', 'reports/report.pdf')
  #     archive.add_directory('photos/')
  #     archive.add_data('notes/readme.txt', "generated\n")
  #   end
  #
  #   Omnizip::Archive.open('backup.7z') do |archive|
  #     archive.entries.each { |e| puts "#{e.name} (#{e.size})" }
  #     archive.read('notes/readme.txt')
  #     archive.extract_all('output/')
  #   end
  #
  # The format is resolved from the output path's extension when
  # +format:+ is not given explicitly, exactly like the convenience
  # methods. Passwords are supported for 7z only (ZIP writing and
  # reading have no encryption support); asking for one elsewhere
  # raises rather than silently producing an unprotected archive.
  module Archive
    autoload :Builder, "omnizip/archive/builder"
    autoload :ReaderSession, "omnizip/archive/reader_session"

    # Metadata record yielded by ReaderSession#entries. The +size+
    # member intentionally shadows Struct#size: the documented
    # contract is entry size in bytes, not the member count.
    # rubocop:disable-next Lint/StructNewOverride -- documented byte size
    Entry = Struct.new(:name, :size, :directory, :mtime, keyword_init: true) do
      def directory?
        directory
      end
    end

    PASSWORD_FORMATS = %i[seven_zip rar].freeze
    private_constant :PASSWORD_FORMATS

    class << self
      # Create an archive, yielding a Builder that translates the
      # documented +add_file+/+add_directory+/+add_data+ calls onto
      # the resolved handler. Returns the archive path.
      def create(path, format: Convenience::DEFAULT_FORMAT, **options, &block)
        resolved = Omnizip.resolve_archive_format(path, format)
        check_password_support!(resolved, options[:password])

        Omnizip::ArchiveHandler.for(resolved).create(path, **options) do |proxy|
          block&.call(Builder.new(proxy))
        end
        path
      end

      # Open an archive for reading, yielding a ReaderSession. Without
      # a block, returns the session. An explicit +password:+ wins
      # over ENV['OMNIZIP_PASSWORD'].
      def open(path, password: nil, **options, &block)
        resolved = Omnizip.resolve_archive_format(
          path, Convenience::DEFAULT_FORMAT, writing: false
        )
        pw = password || ENV.fetch("OMNIZIP_PASSWORD", nil)
        check_password_support!(resolved, pw)

        options[:password] = pw if pw
        session = ReaderSession.new(
          Omnizip::ArchiveHandler.for(resolved), path, options
        )
        return session unless block

        yield session
      end

      private

      def check_password_support!(resolved, password)
        return unless password && !PASSWORD_FORMATS.include?(resolved)

        raise Omnizip::UnsupportedFormatError,
              "password is only supported for #{PASSWORD_FORMATS.join(', ')}; " \
              "#{resolved.inspect} has no encryption support"
      end
    end
  end
end
