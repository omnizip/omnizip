# frozen_string_literal: true

module Omnizip
  # Mix-in that establishes the common contract every archive entry
  # satisfies, regardless of format.
  #
  # Each format-specific entry class (Zip::Entry, Tar::Entry,
  # SevenZip::Models::FileEntry, Iso::DirectoryRecord, Ole::Dirent,
  # Xar::Entry, Rpm::Entry, Msi::Entry, Cpio::Entry, Rar3::Entry,
  # Rar5::Entry, Xz::Entry, Metadata::EntryMetadata) includes this
  # module so callers can rely on a single narrow interface instead
  # of duck-typing through `respond_to?(:name) / :path / :filename`
  # cascades.
  #
  # Including classes MUST override the four methods below. The
  # defaults raise `NotImplementedError` to surface missing
  # implementations at call time rather than at include time.
  module Entry
    # @return [String, nil] in-archive path, or nil if the entry has
    #   no name (e.g. empty anti-entry)
    def entry_name
      raise NotImplementedError,
            "#{self.class} must implement #entry_name"
    end

    # @return [Boolean] true if the entry is a directory
    def entry_directory?
      raise NotImplementedError,
            "#{self.class} must implement #entry_directory?"
    end

    # @return [Integer, nil] uncompressed size in bytes
    def entry_size
      raise NotImplementedError,
            "#{self.class} must implement #entry_size"
    end

    # @return [Time, nil] modification time
    def entry_mtime
      raise NotImplementedError,
            "#{self.class} must implement #entry_mtime"
    end
  end
end
