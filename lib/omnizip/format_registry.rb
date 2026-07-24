# frozen_string_literal: true


require "omnizip"
module Omnizip
  class FormatRegistry < Omnizip::Registry
    BUILTIN_FORMATS = {
      ".7z" => "Omnizip::Formats::SevenZip::Reader",
      ".zip" => "Omnizip::Formats::Zip",
      ".rar" => "Omnizip::Formats::Rar::Reader",
      ".tar" => "Omnizip::Formats::Tar",
      ".gz" => "Omnizip::Formats::Gzip",
      ".gzip" => "Omnizip::Formats::Gzip",
      ".bz2" => "Omnizip::Formats::Bzip2File",
      ".bzip2" => "Omnizip::Formats::Bzip2File",
      ".xz" => "Omnizip::Formats::Xz",
      ".msi" => "Omnizip::Formats::Msi",
      ".msp" => "Omnizip::Formats::Msi",
      ".cpio" => "Omnizip::Formats::Cpio::Reader",
      ".iso" => "Omnizip::Formats::Iso::Reader",
      ".xar" => "Omnizip::Formats::Xar::Reader",
      ".lz" => "Omnizip::Formats::Lzip",
      ".lzip" => "Omnizip::Formats::Lzip",
      ".lzma" => "Omnizip::Formats::LzmaAlone",
      ".ole" => "Omnizip::Formats::Ole::Storage",
      ".doc" => "Omnizip::Formats::Ole::Storage",
      ".xls" => "Omnizip::Formats::Ole::Storage",
      ".ppt" => "Omnizip::Formats::Ole::Storage",
    }.freeze

    class << self
      def label
        "Format"
      end

      def normalize_key(extension)
        ext = extension.to_s
        ext = ".#{ext}" unless ext.start_with?(".")
        ext.downcase
      end

      def get(extension)
        normalized = normalize_key(extension)
        handler = storage[normalized]
        return resolve_handler(handler, extension) if handler

        trigger = lazy_triggers[normalized]
        if trigger
          synchronize { lazy_triggers.delete(normalized) }
          trigger.call
          handler = storage[normalized]
          return resolve_handler(handler, extension) if handler
        end

        nil
      end

      def supported?(extension)
        registered?(extension) || lazy_triggers.key?(normalize_key(extension))
      end
      alias supported_formats available

      def resolve_constant(name)
        return nil unless name.is_a?(String)

        parts = name.split("::")
        parts.shift if parts.empty? || parts.first.empty?

        constant = Object
        parts.each do |n|
          return nil unless constant.const_defined?(n, false)

          constant = constant.const_get(n)
        end
        constant
      rescue StandardError
        nil
      end

      private

      def resolve_handler(handler, _original_extension)
        return nil if handler.nil?
        return handler if handler.is_a?(Class) || handler.is_a?(Module)

        resolve_constant(handler)
      end
    end
  end
end

# Lazy triggers — explicitly re-register on each miss so the entry
# survives reset!. Object.const_get alone doesn't re-run the file body
# once the constant is loaded.
Omnizip::FormatRegistry::BUILTIN_FORMATS.each do |ext, const_path|
  Omnizip::FormatRegistry.register_lazy(ext) do
    handler = Object.const_get(const_path)
    # Register under the original extension; some formats (e.g. Rar)
    # store a string class path that needs resolve_constant on get.
    Omnizip::FormatRegistry.register(ext, handler)
  end
end
