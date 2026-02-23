# frozen_string_literal: true

module Omnizip
  module Formats
    module SevenZip
      # Models namespace for SevenZip archive data structures
      module Models
        def self.autoload!(registry)
          registry.autoload(:FileEntry,
                            "omnizip/formats/seven_zip/models/file_entry")
          registry.autoload(:CoderInfo,
                            "omnizip/formats/seven_zip/models/coder_info")
          registry.autoload(:StreamInfo,
                            "omnizip/formats/seven_zip/models/stream_info")
          registry.autoload(:Folder, "omnizip/formats/seven_zip/models/folder")
        end
      end
    end
  end
end
