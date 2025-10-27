# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/omnizip/zip/file"

RSpec.describe Omnizip::Zip::File do
  let(:temp_dir) { Dir.mktmpdir }
  let(:zip_path) { File.join(temp_dir, "test.zip") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".open" do
    context "with existing file" do
      before do
        # Create a test ZIP file
        described_class.open(zip_path, create: true) do |zip|
          zip.add("test.txt") { "Hello, World!" }
        end
      end

      it "opens existing archive" do
        described_class.open(zip_path) do |zip|
          expect(zip.entries.size).to eq(1)
          expect(zip.entries.first.name).to eq("test.txt")
        end
      end

      it "returns file object if no block given" do
        zip = described_class.open(zip_path)
        expect(zip).to be_a(described_class)
        expect(zip.entries.size).to eq(1)
        zip.close
      end
    end

    context "with create flag" do
      it "creates new archive" do
        described_class.open(zip_path, create: true) do |zip|
          expect(zip.entries).to be_empty
        end
        expect(File.exist?(zip_path)).to be true
      end
    end

    context "with non-existent file" do
      it "raises error without create flag" do
        expect {
          described_class.open("nonexistent.zip")
        }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe ".create" do
    it "creates new archive" do
      described_class.create(zip_path) do |zip|
        zip.add("file.txt") { "content" }
      end

      expect(File.exist?(zip_path)).to be true

      described_class.open(zip_path) do |zip|
        expect(zip.entries.size).to eq(1)
      end
    end
  end

  describe "#initialize" do
    it "loads existing archive" do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "content" }
      end

      zip = described_class.new(zip_path)
      expect(zip.entries.size).to eq(1)
      zip.close
    end
  end

  describe "#add" do
    it "adds file from block" do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "Hello" }
        expect(zip.entries.size).to eq(1)
        expect(zip.get_entry("test.txt")).not_to be_nil
      end
    end

    it "adds file from path" do
      source_file = File.join(temp_dir, "source.txt")
      File.write(source_file, "Source content")

      described_class.open(zip_path, create: true) do |zip|
        zip.add("archived.txt", source_file)
        expect(zip.entries.size).to eq(1)
      end

      described_class.open(zip_path) do |zip|
        content = zip.read("archived.txt")
        expect(content).to eq("Source content")
      end
    end

    it "raises error without source or block" do
      described_class.open(zip_path, create: true) do |zip|
        expect {
          zip.add("test.txt")
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#get_entry" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("file1.txt") { "content1" }
        zip.add("file2.txt") { "content2" }
      end
    end

    it "returns entry by name" do
      described_class.open(zip_path) do |zip|
        entry = zip.get_entry("file1.txt")
        expect(entry).not_to be_nil
        expect(entry.name).to eq("file1.txt")
      end
    end

    it "returns nil for non-existent entry" do
      described_class.open(zip_path) do |zip|
        expect(zip.get_entry("nonexistent.txt")).to be_nil
      end
    end
  end

  describe "#find_entry" do
    it "is alias for get_entry" do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "content" }
        expect(zip.method(:find_entry)).to eq(zip.method(:get_entry))
      end
    end
  end

  describe "#get_input_stream" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "Test content" }
      end
    end

    it "reads entry content with block" do
      described_class.open(zip_path) do |zip|
        content = nil
        zip.get_input_stream("test.txt") do |stream|
          content = stream.read
        end
        expect(content).to eq("Test content")
      end
    end

    it "returns content without block" do
      described_class.open(zip_path) do |zip|
        content = zip.get_input_stream("test.txt")
        expect(content).to eq("Test content")
      end
    end

    it "accepts Entry object" do
      described_class.open(zip_path) do |zip|
        entry = zip.get_entry("test.txt")
        content = zip.get_input_stream(entry)
        expect(content).to eq("Test content")
      end
    end
  end

  describe "#read" do
    it "is alias for get_input_stream" do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "content" }
        expect(zip.method(:read)).to eq(zip.method(:get_input_stream))
      end
    end
  end

  describe "#each" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("file1.txt") { "content1" }
        zip.add("file2.txt") { "content2" }
        zip.add("file3.txt") { "content3" }
      end
    end

    it "iterates over all entries" do
      described_class.open(zip_path) do |zip|
        names = []
        zip.each { |entry| names << entry.name }
        expect(names).to contain_exactly("file1.txt", "file2.txt", "file3.txt")
      end
    end
  end

  describe "#extract" do
    let(:extract_path) { File.join(temp_dir, "extracted.txt") }

    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "Extracted content" }
      end
    end

    it "extracts entry to path" do
      described_class.open(zip_path) do |zip|
        zip.extract("test.txt", extract_path)
      end

      expect(File.exist?(extract_path)).to be true
      expect(File.read(extract_path)).to eq("Extracted content")
    end

    it "raises error for existing file without block" do
      File.write(extract_path, "existing")

      described_class.open(zip_path) do |zip|
        expect {
          zip.extract("test.txt", extract_path)
        }.to raise_error(/already exists/)
      end
    end

    it "calls block for existing file" do
      File.write(extract_path, "existing")

      described_class.open(zip_path) do |zip|
        overwrite = false
        zip.extract("test.txt", extract_path) do |entry, dest|
          overwrite = true
          true
        end
        expect(overwrite).to be true
      end
    end

    it "accepts Entry object" do
      described_class.open(zip_path) do |zip|
        entry = zip.get_entry("test.txt")
        zip.extract(entry, extract_path)
      end

      expect(File.exist?(extract_path)).to be true
    end
  end

  describe "#remove" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("file1.txt") { "content1" }
        zip.add("file2.txt") { "content2" }
      end
    end

    it "removes entry from archive" do
      described_class.open(zip_path) do |zip|
        expect(zip.entries.size).to eq(2)
        zip.remove("file1.txt")
        expect(zip.entries.size).to eq(1)
        expect(zip.get_entry("file1.txt")).to be_nil
      end
    end
  end

  describe "#rename" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("old_name.txt") { "content" }
      end
    end

    it "renames entry" do
      described_class.open(zip_path) do |zip|
        zip.rename("old_name.txt", "new_name.txt")
        expect(zip.get_entry("old_name.txt")).to be_nil
        expect(zip.get_entry("new_name.txt")).not_to be_nil
      end
    end
  end

  describe "#replace" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "old content" }
      end
    end

    it "replaces entry content" do
      described_class.open(zip_path) do |zip|
        zip.replace("test.txt") { "new content" }
        content = zip.read("test.txt")
        expect(content).to eq("new content")
      end
    end
  end

  describe "#comment" do
    it "gets and sets archive comment" do
      described_class.open(zip_path, create: true) do |zip|
        zip.comment = "Test comment"
        expect(zip.comment).to eq("Test comment")
      end
    end
  end

  describe "#size" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("file1.txt") { "content1" }
        zip.add("file2.txt") { "content2" }
      end
    end

    it "returns number of entries" do
      described_class.open(zip_path) do |zip|
        expect(zip.size).to eq(2)
      end
    end
  end

  describe "#length" do
    it "is alias for size" do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "content" }
        expect(zip.method(:length)).to eq(zip.method(:size))
      end
    end
  end

  describe "#include?" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("test.txt") { "content" }
      end
    end

    it "returns true for existing entry" do
      described_class.open(zip_path) do |zip|
        expect(zip.include?("test.txt")).to be true
      end
    end

    it "returns false for non-existent entry" do
      described_class.open(zip_path) do |zip|
        expect(zip.include?("nonexistent.txt")).to be false
      end
    end
  end

  describe "#names" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("file1.txt") { "content1" }
        zip.add("file2.txt") { "content2" }
      end
    end

    it "returns array of entry names" do
      described_class.open(zip_path) do |zip|
        expect(zip.names).to contain_exactly("file1.txt", "file2.txt")
      end
    end
  end

  describe "#glob" do
    before do
      described_class.open(zip_path, create: true) do |zip|
        zip.add("dir/file1.txt") { "content1" }
        zip.add("dir/file2.rb") { "content2" }
        zip.add("other.txt") { "content3" }
      end
    end

    it "returns matching entries" do
      described_class.open(zip_path) do |zip|
        matches = zip.glob("dir/*.txt")
        expect(matches.size).to eq(1)
        expect(matches.first.name).to eq("dir/file1.txt")
      end
    end

    it "accepts block" do
      described_class.open(zip_path) do |zip|
        names = []
        zip.glob("dir/*") { |entry| names << entry.name }
        expect(names).to contain_exactly("dir/file1.txt", "dir/file2.rb")
      end
    end
  end

  describe "#close" do
    it "commits changes on close" do
      zip = described_class.open(zip_path, create: true)
      zip.add("test.txt") { "content" }
      zip.close

      described_class.open(zip_path) do |zip|
        expect(zip.entries.size).to eq(1)
      end
    end
  end
end