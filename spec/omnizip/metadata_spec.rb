# frozen_string_literal: true

require "spec_helper"
require "omnizip/metadata"
require "omnizip/zip/file"
require "tempfile"

RSpec.describe Omnizip::Metadata do
  let(:test_archive) { Tempfile.new(["test", ".zip"]) }

  before do
    # Create a test archive
    Omnizip::Zip::File.create(test_archive.path) do |zip|
      zip.add("file1.txt") { "content1" }
      zip.add("file2.rb") { "puts 'hello'" }
      zip.add("dir/") # Directory entry
    end
  end

  after do
    test_archive.close
    test_archive.unlink
  end

  describe ".edit_entry" do
    it "edits entry metadata" do
      Omnizip::Zip::File.open(test_archive.path) do |zip|
        entry = zip.get_entry("file1.txt")
        metadata = described_class.edit_entry(entry) do |m|
          m.comment = "Test comment"
          m.unix_permissions = 0o644
        end

        expect(metadata.comment).to eq("Test comment")
        expect(metadata.unix_permissions).to eq(0o644)
      end
    end
  end

  describe ".edit_archive" do
    it "edits archive metadata" do
      Omnizip::Zip::File.open(test_archive.path) do |zip|
        metadata = described_class.edit_archive(zip) do |m|
          m.comment = "Archive comment"
        end

        expect(metadata.comment).to eq("Archive comment")
        expect(zip.comment).to eq("Archive comment")
      end
    end
  end

  describe Omnizip::Metadata::EntryMetadata do
    let(:entry) do
      Omnizip::Zip::File.open(test_archive.path) do |zip|
        return zip.get_entry("file1.txt")
      end
    end

    subject { described_class.new(entry) }

    it "gets and sets comment" do
      subject.comment = "New comment"
      expect(subject.comment).to eq("New comment")
      expect(subject.modified?).to be true
    end

    it "gets and sets modification time" do
      new_time = Time.new(2024, 1, 1, 12, 0, 0)
      subject.mtime = new_time
      expect(subject.mtime.year).to eq(2024)
      expect(subject.modified?).to be true
    end

    it "gets and sets Unix permissions" do
      subject.unix_permissions = 0o755
      expect(subject.unix_permissions).to eq(0o755)
      expect(subject.modified?).to be true
    end

    it "converts to hash" do
      hash = subject.to_h
      expect(hash).to include(:name, :comment, :mtime, :unix_permissions, :size)
    end
  end

  describe Omnizip::Metadata::ArchiveMetadata do
    let(:archive) do
      Omnizip::Zip::File.open(test_archive.path)
    end

    after { archive.close }

    subject { described_class.new(archive) }

    it "gets and sets comment" do
      subject.comment = "Archive comment"
      expect(subject.comment).to eq("Archive comment")
      expect(subject.modified?).to be true
    end

    it "calculates total size" do
      expect(subject.total_size).to be > 0
    end

    it "calculates compression ratio" do
      expect(subject.compression_ratio).to be_between(0.0, 1.0)
    end

    it "counts entries" do
      expect(subject.entry_count).to eq(3)
      expect(subject.file_count).to eq(2)
      expect(subject.directory_count).to eq(1)
    end
  end

  describe Omnizip::Metadata::MetadataValidator do
    subject { described_class.new }

    describe "#validate_comment" do
      it "accepts valid comments" do
        expect { subject.validate_comment("Test") }.not_to raise_error
      end

      it "rejects overly long comments" do
        long_comment = "a" * 70_000
        expect do
          subject.validate_comment(long_comment)
        end.to raise_error(ArgumentError,
                           /too long/)
      end
    end

    describe "#validate_time" do
      it "accepts valid times" do
        expect { subject.validate_time(Time.now) }.not_to raise_error
      end

      it "rejects times outside DOS range" do
        expect do
          subject.validate_time(Time.new(1970, 1,
                                         1))
        end.to raise_error(ArgumentError, /DOS range/)
      end
    end

    describe "#validate_permissions" do
      it "accepts valid permissions" do
        expect { subject.validate_permissions(0o644) }.not_to raise_error
      end

      it "rejects invalid permissions" do
        expect do
          subject.validate_permissions(0o1000)
        end.to raise_error(ArgumentError,
                           /out of range/)
      end
    end
  end

  describe Omnizip::Metadata::MetadataEditor do
    let(:archive) do
      Omnizip::Zip::File.open(test_archive.path)
    end

    after { archive.close }

    subject { described_class.new(archive) }

    it "sets all timestamps" do
      new_time = Time.new(2024, 6, 1, 12, 0, 0)
      subject.set_all_timestamps(new_time)
      subject.commit

      expect(subject.modified?).to be false
    end

    it "normalizes permissions" do
      subject.normalize_permissions
      subject.commit

      archive.entries.each do |entry|
        next if entry.directory?

        expect(entry.unix_perms).to eq(0o644)
      end
    end

    it "strips comments" do
      # First add some comments
      archive.entries.first.comment = "test"
      archive.comment = "test"

      subject.strip_comments
      subject.commit

      expect(archive.comment).to eq("")
      archive.entries.each do |entry|
        expect(entry.comment).to eq("")
      end
    end

    it "sets comments matching pattern" do
      subject.set_comment_matching("*.rb", "Ruby file")
      subject.commit

      rb_file = archive.get_entry("file2.rb")
      expect(rb_file.comment).to eq("Ruby file")
    end

    it "sets permissions matching pattern" do
      subject.set_permissions_matching("*.rb", 0o755)
      subject.commit

      rb_file = archive.get_entry("file2.rb")
      expect(rb_file.unix_perms).to eq(0o755)
    end
  end

  describe Omnizip::Metadata::MetadataRegistry do
    it "registers format support" do
      expect(described_class.supports?(:zip, :comment)).to be true
      expect(described_class.supports?(:zip, :mtime)).to be true
    end

    it "returns supported fields" do
      fields = described_class.supported_fields(:zip)
      expect(fields).to include(:comment, :mtime, :unix_permissions)
    end

    it "returns all formats" do
      expect(described_class.formats).to include(:zip, :seven_zip)
    end
  end
end
