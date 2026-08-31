# frozen_string_literal: true

module Omnizip
  # Unified archive handler interface for the Convenience module.
  #
  # Each format that wants to participate in Omnizip.compress_file /
  # extract_archive / etc. registers a Handler here. The Handler exposes
  # a small canonical API (+create+, +open+, +extract_to+, +list+) that
  # the Convenience module calls; the Handler then delegates to the
  # format-specific reader/writer.
  #
  # @example Register a format
  #   Omnizip::ArchiveHandler.register(:tar, TarHandler.new)
  #
  # @example Use from a caller
  #   Omnizip::ArchiveHandler.for(:tar).create(path) { |w| w.add_file(...) }
  module ArchiveHandler
    @handlers = {}

    class << self
      # Register a handler for a format symbol.
      #
      # @param format [Symbol] e.g. +:zip+, +:tar+
      # @param handler [Object] responding to the Handler interface
      # @return [void]
      def register(format, handler)
        @handlers[format.to_sym] = handler
      end

      # Look up the handler for +format+. Triggers the registered lazy
      # load constant if the format is one of the built-ins.
      #
      # @param format [Symbol]
      # @return [Object]
      # @raise [Omnizip::UnsupportedFormatError] if +format+ is unknown
      def for(format)
        handler = @handlers[format.to_sym]
        return handler if handler

        trigger = LAZY_LOAD_TRIGGERS[format.to_sym]
        if trigger
          trigger.call
          handler = @handlers[format.to_sym]
          return handler if handler
        end

        raise Omnizip::UnsupportedFormatError,
              "No archive handler registered for #{format.inspect}. " \
              "Registered: #{@handlers.keys.join(', ')}"
      end

      # List of registered format names.
      #
      # @return [Array<Symbol>]
      def available
        @handlers.keys
      end

      # Remove a handler (primarily for testing).
      #
      # @return [void]
      def unregister(format)
        @handlers.delete(format.to_sym)
      end
    end

    # Lazy triggers — referencing the constant autoloads the handler's
    # file, which then self-registers at the bottom of the file.
    LAZY_LOAD_TRIGGERS = {
      zip: -> { Omnizip::ArchiveHandlers::ZipHandler },
      rpm: -> { Omnizip::ArchiveHandlers::RpmHandler },
      xar: -> { Omnizip::ArchiveHandlers::XarHandler },
      ole: -> { Omnizip::ArchiveHandlers::OleHandler },
      tar: -> { Omnizip::ArchiveHandlers::TarHandler },
      seven_zip: -> { Omnizip::ArchiveHandlers::SevenZipHandler },
      rar: -> { Omnizip::ArchiveHandlers::RarHandler },
      cpio: -> { Omnizip::ArchiveHandlers::CpioHandler },
      iso: -> { Omnizip::ArchiveHandlers::IsoHandler },
    }.freeze
    private_constant :LAZY_LOAD_TRIGGERS
  end
end
