# frozen_string_literal: true

module Omnizip
  # CLI command implementations
  module Commands
    autoload :CompressCommand, "omnizip/commands/compress_command"
    autoload :DecompressCommand, "omnizip/commands/decompress_command"
    autoload :ListCommand, "omnizip/commands/list_command"
    autoload :ArchiveCreateCommand, "omnizip/commands/archive_create_command"
    autoload :ArchiveExtractCommand, "omnizip/commands/archive_extract_command"
    autoload :ArchiveListCommand, "omnizip/commands/archive_list_command"
    autoload :ProfileListCommand, "omnizip/commands/profile_list_command"
    autoload :ProfileShowCommand, "omnizip/commands/profile_show_command"
    autoload :MetadataCommand, "omnizip/commands/metadata_command"
    autoload :ArchiveVerifyCommand, "omnizip/commands/archive_verify_command"
    autoload :ArchiveRepairCommand, "omnizip/commands/archive_repair_command"
    autoload :ParityCreateCommand, "omnizip/commands/parity_create_command"
    autoload :ParityVerifyCommand, "omnizip/commands/parity_verify_command"
    autoload :ParityRepairCommand, "omnizip/commands/parity_repair_command"
  end
end
