# frozen_string_literal: true

module Omnizip
  # Archive handler namespace. Each format ships a Handler class here
  # that adapts its format-specific API to the canonical contract
  # documented on +Omnizip::ArchiveHandler+.
  module ArchiveHandlers
    autoload :ZipHandler, "omnizip/archive_handlers/zip_handler"
    autoload :TarHandler, "omnizip/archive_handlers/tar_handler"
  end
end
