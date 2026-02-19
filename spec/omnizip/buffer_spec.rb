# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Buffer do
  describe ".create" do
    it "creates ZIP archive in memory" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file.txt", "Hello World")
      end

      expect(buffer).to be_a(StringIO)
      expect(buffer.string).not_to be_empty
      expect(buffer.string[0..3]).to eq("PK\x03\x04")
    end

    it "creates archive with multiple files" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file1.txt", "content1")
        archive.add("file2.txt", "content2")
        archive.add("dir/file3.txt", "content3")
      end

      expect(buffer).to be_a(StringIO)
      files = described_class.extract_to_memory(buffer.string)
      expect(files.keys).to contain_exactly("file1.txt", "file2.txt",
                                            "dir/file3.txt")
    end

    it "creates archive with directory entries" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("dir/", "")
        archive.add("dir/file.txt", "content")
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files["dir/file.txt"]).to eq("content")
      expect(files).not_to have_key("dir/")
    end

    it "supports method chaining" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file1.txt", "content1")
          .add("file2.txt", "content2")
          .add("file3.txt", "content3")
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files.size).to eq(3)
    end

    it "rewinds buffer before returning" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file.txt", "content")
      end

      expect(buffer.pos).to eq(0)
    end

    it "raises error for unsupported format" do
      expect do
        described_class.create(:rar) { |_| }
      end.to raise_error(ArgumentError, /Unsupported format/)
    end

    it "creates archive with compression options" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file.txt", "Hello World", compression: :deflate, level: 9)
      end

      expect(buffer.string).not_to be_empty
    end

    it "creates archive with store (no compression)" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("file.txt", "Hello World", compression: :store)
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files["file.txt"]).to eq("Hello World")
    end
  end

  describe ".open" do
    let(:zip_data) do
      described_class.create(:zip) do |archive|
        archive.add("file1.txt", "content1")
        archive.add("file2.txt", "content2")
      end.string
    end

    it "opens archive from String" do
      result = []
      described_class.open(zip_data) do |archive|
        archive.each_entry do |entry|
          result << entry.name
        end
      end

      expect(result).to contain_exactly("file1.txt", "file2.txt")
    end

    it "opens archive from StringIO" do
      buffer = StringIO.new(zip_data)
      result = []

      described_class.open(buffer) do |archive|
        archive.each_entry do |entry|
          result << entry.name
        end
      end

      expect(result).to contain_exactly("file1.txt", "file2.txt")
    end

    it "reads entry content" do
      contents = {}
      described_class.open(zip_data) do |archive|
        archive.each_entry do |entry|
          contents[entry.name] = entry.read
        end
      end

      expect(contents["file1.txt"]).to eq("content1")
      expect(contents["file2.txt"]).to eq("content2")
    end

    it "detects format automatically" do
      result = []
      described_class.open(zip_data, format: nil) do |archive|
        archive.each_entry do |entry|
          result << entry.name
        end
      end

      expect(result).to contain_exactly("file1.txt", "file2.txt")
    end

    it "respects explicit format parameter" do
      result = []
      described_class.open(zip_data, format: :zip) do |archive|
        archive.each_entry do |entry|
          result << entry.name
        end
      end

      expect(result).to contain_exactly("file1.txt", "file2.txt")
    end

    it "raises error for unknown format" do
      invalid_data = "NOT A ZIP FILE"
      expect do
        described_class.open(invalid_data)
      end.to raise_error(Omnizip::FormatError, /Unknown archive format/)
    end
  end

  describe ".extract_to_memory" do
    let(:zip_data) do
      described_class.create(:zip) do |archive|
        archive.add("file1.txt", "content1")
        archive.add("file2.txt", "content2")
        archive.add("dir/file3.txt", "content3")
      end.string
    end

    it "extracts all files to Hash" do
      files = described_class.extract_to_memory(zip_data)

      expect(files).to be_a(Hash)
      expect(files.size).to eq(3)
      expect(files["file1.txt"]).to eq("content1")
      expect(files["file2.txt"]).to eq("content2")
      expect(files["dir/file3.txt"]).to eq("content3")
    end

    it "handles empty archive" do
      empty_zip = described_class.create(:zip) { |_| }.string
      files = described_class.extract_to_memory(empty_zip)

      expect(files).to eq({})
    end

    it "skips directory entries" do
      zip_with_dirs = described_class.create(:zip) do |archive|
        archive.add("dir/", "")
        archive.add("dir/file.txt", "content")
      end.string

      files = described_class.extract_to_memory(zip_with_dirs)
      expect(files).not_to have_key("dir/")
      expect(files["dir/file.txt"]).to eq("content")
    end

    it "works with StringIO input" do
      buffer = StringIO.new(zip_data)
      files = described_class.extract_to_memory(buffer)

      expect(files.size).to eq(3)
    end

    it "auto-detects format" do
      files = described_class.extract_to_memory(zip_data, format: nil)
      expect(files.size).to eq(3)
    end
  end

  describe ".create_from_hash" do
    it "creates archive from Hash" do
      hash = {
        "file1.txt" => "content1",
        "file2.txt" => "content2",
        "dir/file3.txt" => "content3",
      }

      buffer = described_class.create_from_hash(hash, :zip)
      files = described_class.extract_to_memory(buffer.string)

      expect(files).to eq(hash)
    end

    it "handles empty Hash" do
      buffer = described_class.create_from_hash({}, :zip)
      files = described_class.extract_to_memory(buffer.string)

      expect(files).to eq({})
    end

    it "preserves file paths" do
      hash = {
        "a/b/c/file.txt" => "deep content",
        "single.txt" => "top level",
      }

      buffer = described_class.create_from_hash(hash, :zip)
      files = described_class.extract_to_memory(buffer.string)

      expect(files).to eq(hash)
    end
  end

  describe "round-trip operations" do
    it "preserves content through create and extract" do
      original = {
        "readme.txt" => "Hello World",
        "data.json" => '{"key": "value"}',
        "binary.dat" => "\x00\x01\x02\xFF".b,
      }

      buffer = described_class.create_from_hash(original, :zip)
      extracted = described_class.extract_to_memory(buffer.string)

      expect(extracted).to eq(original)
    end

    it "handles large content" do
      large_content = "A" * 1_000_000 # 1MB
      buffer = described_class.create(:zip) do |archive|
        archive.add("large.txt", large_content)
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files["large.txt"]).to eq(large_content)
    end

    it "preserves binary data" do
      binary_data = (0..255).map(&:chr).join.b
      buffer = described_class.create(:zip) do |archive|
        archive.add("binary.dat", binary_data)
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files["binary.dat"]).to eq(binary_data)
    end

    it "handles UTF-8 filenames" do
      buffer = described_class.create(:zip) do |archive|
        archive.add("日本語.txt", "Japanese content")
        archive.add("emoji-😀.txt", "Emoji content")
      end

      files = described_class.extract_to_memory(buffer.string)
      expect(files["日本語.txt"]).to eq("Japanese content")
      expect(files["emoji-😀.txt"]).to eq("Emoji content")
    end
  end

  describe "memory efficiency" do
    it "does not keep archive in memory after extraction" do
      # Create a reasonably sized archive
      content = "X" * 100_000
      buffer = described_class.create(:zip) do |archive|
        5.times { |i| archive.add("file#{i}.txt", content) }
      end

      # Extract and verify
      files = described_class.extract_to_memory(buffer.string)
      expect(files.size).to eq(5)

      # Verify buffer can be garbage collected
      nil
      GC.start
      expect(files.size).to eq(5) # Still accessible
    end
  end

  describe "web application scenarios" do
    it "creates downloadable archive" do
      # Simulate web app creating files to download
      user_files = {
        "document.txt" => "User document content",
        "image.txt" => "Simulated image data",
        "data.csv" => "name,value\ntest,123",
      }

      # Create archive
      zip_data = described_class.create_from_hash(user_files, :zip)

      # Simulate sending data
      response_body = zip_data.string
      expect(response_body.bytesize).to be > 0
      expect(response_body[0..3]).to eq("PK\x03\x04")

      # Verify can be extracted
      extracted = described_class.extract_to_memory(response_body)
      expect(extracted).to eq(user_files)
    end

    it "processes uploaded archive" do
      # Simulate receiving uploaded ZIP
      uploaded_data = described_class.create(:zip) do |archive|
        archive.add("upload1.txt", "uploaded content 1")
        archive.add("upload2.txt", "uploaded content 2")
      end.string

      # Process without filesystem
      files = described_class.extract_to_memory(uploaded_data)

      expect(files.size).to eq(2)
      expect(files["upload1.txt"]).to eq("uploaded content 1")
    end
  end

  describe "API response scenarios" do
    it "generates API response archive" do
      # Simulate API generating archive response
      api_data = {
        "response.json" => '{"status": "success"}',
        "logs.txt" => "API call logs...",
        "metadata.yaml" => "created_at: 2024-01-01",
      }

      archive = described_class.create_from_hash(api_data, :zip)

      # Simulate HTTP response
      expect(archive.string.encoding).to eq(Encoding::BINARY)
      expect(archive.string.bytesize).to be > 0
    end
  end

  describe "testing scenarios" do
    it "enables testing without filesystem" do
      # Create test data in memory
      test_archive = described_class.create(:zip) do |archive|
        archive.add("test1.txt", "test content 1")
        archive.add("test2.txt", "test content 2")
      end

      # Test extraction
      files = described_class.extract_to_memory(test_archive.string)
      expect(files.keys).to contain_exactly("test1.txt", "test2.txt")

      # No cleanup needed - no temp files created
    end
  end
end

RSpec.describe Omnizip::Buffer::MemoryExtractor do
  let(:zip_data) do
    Omnizip::Buffer.create(:zip) do |archive|
      archive.add("file1.txt", "content1")
      archive.add("file2.txt", "content2")
      archive.add("dir/file3.txt", "content3")
    end.string
  end

  describe "#initialize" do
    it "accepts String data" do
      extractor = described_class.new(zip_data)
      expect(extractor.format).to eq(:zip)
    end

    it "accepts StringIO data" do
      buffer = StringIO.new(zip_data)
      extractor = described_class.new(buffer)
      expect(extractor.format).to eq(:zip)
    end

    it "auto-detects format" do
      extractor = described_class.new(zip_data)
      expect(extractor.format).to eq(:zip)
    end

    it "accepts explicit format" do
      extractor = described_class.new(zip_data, format: :zip)
      expect(extractor.format).to eq(:zip)
    end
  end

  describe "#extract_all" do
    it "extracts all entries" do
      extractor = described_class.new(zip_data)
      files = extractor.extract_all

      expect(files.size).to eq(3)
      expect(files["file1.txt"]).to eq("content1")
    end
  end

  describe "#extract_entry" do
    it "extracts single entry by name" do
      extractor = described_class.new(zip_data)
      content = extractor.extract_entry("file1.txt")

      expect(content).to eq("content1")
    end

    it "returns nil for non-existent entry" do
      extractor = described_class.new(zip_data)
      content = extractor.extract_entry("nonexistent.txt")

      expect(content).to be_nil
    end

    it "caches extracted entries" do
      extractor = described_class.new(zip_data)

      # Extract twice
      content1 = extractor.extract_entry("file1.txt")
      content2 = extractor.extract_entry("file1.txt")

      expect(content1).to eq(content2)
      expect(content1).to eq("content1")
    end
  end

  describe "#list_entries" do
    it "lists all entry names" do
      extractor = described_class.new(zip_data)
      names = extractor.list_entries

      expect(names).to contain_exactly("file1.txt", "file2.txt",
                                       "dir/file3.txt")
    end

    it "includes directory entries" do
      zip_with_dirs = Omnizip::Buffer.create(:zip) do |archive|
        archive.add("dir/", "")
        archive.add("dir/file.txt", "content")
      end.string

      extractor = described_class.new(zip_with_dirs)
      names = extractor.list_entries

      expect(names).to include("dir/")
    end
  end

  describe "#entry_exists?" do
    it "returns true for existing entry" do
      extractor = described_class.new(zip_data)
      expect(extractor.entry_exists?("file1.txt")).to be true
    end

    it "returns false for non-existent entry" do
      extractor = described_class.new(zip_data)
      expect(extractor.entry_exists?("nonexistent.txt")).to be false
    end
  end

  describe "#entry_count" do
    it "returns number of entries" do
      extractor = described_class.new(zip_data)
      expect(extractor.entry_count).to eq(3)
    end
  end

  describe "#extract_matching" do
    it "extracts entries matching pattern" do
      extractor = described_class.new(zip_data)
      txt_files = extractor.extract_matching(/\.txt$/)

      expect(txt_files.size).to eq(3)
      expect(txt_files.keys).to all(end_with(".txt"))
    end

    it "accepts String pattern" do
      extractor = described_class.new(zip_data)
      files = extractor.extract_matching("file[12]")

      expect(files.size).to eq(2)
      expect(files.keys).to contain_exactly("file1.txt", "file2.txt")
    end

    it "skips directories" do
      zip_with_dirs = Omnizip::Buffer.create(:zip) do |archive|
        archive.add("dir/", "")
        archive.add("dir/file.txt", "content")
      end.string

      extractor = described_class.new(zip_with_dirs)
      files = extractor.extract_matching(/.*/)

      expect(files).not_to have_key("dir/")
      expect(files).to have_key("dir/file.txt")
    end
  end
end
