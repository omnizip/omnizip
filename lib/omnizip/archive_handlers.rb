# frozen_string_literal: true

module Omnizip
  # Archive handler namespace. Each format ships a Handler class here
  # that adapts its format-specific API to the canonical contract
  # documented on +Omnizip::ArchiveHandler+.
  module ArchiveHandlers
    autoload :ZipHandler, "omnizip/archive_handlers/zip_handler"
    autoload :TarHandler, "omnizip/archive_handlers/tar_handler"
    autoload :SevenZipHandler, "omnizip/archive_handlers/seven_zip_handler"
    autoload :RarHandler, "omnizip/archive_handlers/rar_handler"
    autoload :CpioHandler, "omnizip/archive_handlers/cpio_handler"
      autoload :RpmHandler, "omnizip/archive_handlers/rpm_handler"
      autoload :XarHandler, "omnizip/archive_handlers/xar_handler"
      autoload :OleHandler, "omnizip/archive_handlers/ole_handler"
    autoload :IsoHandler, "omnizip/archive_handlers/iso_handler"
  end
end
