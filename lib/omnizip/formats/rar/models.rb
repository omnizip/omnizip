# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # Models namespace for RAR archive data structures
      module Models
        autoload :RarEntry, "omnizip/formats/rar/models/rar_entry"
        autoload :RarVolume, "omnizip/formats/rar/models/rar_volume"
        autoload :RarArchive, "omnizip/formats/rar/models/rar_archive"
      end
    end
  end
end
