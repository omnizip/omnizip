# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "ZIP Format Integration" do
  let(:fixtures_dir) { File.expand_path("../../../fixtures/zip", __dir__) }

  describe "reading standard ZIP files" do
    it "reads a simple deflated file" do
      zip_path = File.join(fixtures_dir, "simple_deflate.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      expect(reader.entries.size).to eq(1)
      entry = reader.entries.first
      expect(entry.filename).to eq("hello.txt")
      expect(entry.compression_method).to eq(Omnizip::Formats::Zip::Constants::COMPRESSION_DEFLATE)
    end

    it "reads a ZIP with directory structure" do
      zip_path = File.join(fixtures_dir, "with_directory.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      expect(reader.entries.size).to be > 1

      # Should have both files and directories
      files = reader.entries.reject(&:directory?)
      dirs = reader.entries.select(&:directory?)

      expect(files).not_to be_empty
      expect(dirs).not_to be_empty
    end

    it "reads a ZIP with multiple files" do
      zip_path = File.join(fixtures_dir, "multi_file.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      expect(reader.entries.size).to eq(2)
      filenames = reader.entries.map(&:filename).sort
      expect(filenames).to include("hello.txt", "data.txt")
    end

    it "reads a ZIP with no compression (Store method)" do
      zip_path = File.join(fixtures_dir, "no_compression.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      entry = reader.entries.first
      expect(entry.compression_method).to eq(Omnizip::Formats::Zip::Constants::COMPRESSION_STORE)
      expect(entry.compressed_size).to eq(entry.uncompressed_size)
    end

    it "reads a large text file" do
      zip_path = File.join(fixtures_dir, "large_text.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      entry = reader.entries.first
      expect(entry.filename).to eq("large.txt")
      expect(entry.uncompressed_size).to be > 50_000
      expect(entry.compressed_size).to be < entry.uncompressed_size
    end
  end

  describe "extracting files" do
    it "extracts a simple file correctly" do
      zip_path = File.join(fixtures_dir, "simple_deflate.zip")

      Dir.mktmpdir do |tmpdir|
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        reader.extract_all(tmpdir)

        extracted_file = File.join(tmpdir, "hello.txt")
        expect(File.exist?(extracted_file)).to be true
        content = File.read(extracted_file)
        expect(content).to eq("Hello, World!\n" * 50)
      end
    end

    it "extracts directory structure correctly" do
      zip_path = File.join(fixtures_dir, "with_directory.zip")

      Dir.mktmpdir do |tmpdir|
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        reader.extract_all(tmpdir)

        # Check that directories exist
        subdir = File.join(tmpdir, "subdir")
        expect(File.directory?(subdir)).to be true

        # Check nested file
        nested_file = File.join(subdir, "nested.txt")
        expect(File.exist?(nested_file)).to be true if File.exist?(File.join(tmpdir, "subdir"))
      end
    end

    it "preserves file content during extraction" do
      zip_path = File.join(fixtures_dir, "large_text.zip")

      Dir.mktmpdir do |tmpdir|
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        reader.extract_all(tmpdir)

        extracted_file = File.join(tmpdir, "large.txt")
        content = File.read(extracted_file)

        # Verify content integrity
        expect(content.lines.count).to eq(2500)
        expect(content.lines.first.strip).to eq("This is a test line for compression.")
      end
    end
  end

  describe "write and read round-trip" do
    it "creates a ZIP that can be read back" do
      Dir.mktmpdir do |tmpdir|
        zip_path = File.join(tmpdir, "test.zip")

        # Write ZIP
        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_data("test.txt", "Test content\n")
        writer.add_data("data.txt", "Some data" * 100)
        writer.write

        # Read it back
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        expect(reader.entries.size).to eq(2)

        # Extract and verify
        output_dir = File.join(tmpdir, "extracted")
        reader.extract_all(output_dir)

        expect(File.read(File.join(output_dir, "test.txt"))).to eq("Test content\n")
        expect(File.read(File.join(output_dir, "data.txt"))).to eq("Some data" * 100)
      end
    end

    it "handles directory entries correctly" do
      Dir.mktmpdir do |tmpdir|
        zip_path = File.join(tmpdir, "dirs.zip")

        # Write ZIP with directories
        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_directory("folder")
        writer.add_data("folder/file.txt", "In folder")
        writer.write

        # Read it back
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        expect(reader.entries.size).to eq(2)

        dir_entry = reader.entries.find { |e| e.directory? }
        expect(dir_entry).not_to be_nil
        expect(dir_entry.filename).to eq("folder/")
      end
    end

    it "supports different compression methods" do
      Dir.mktmpdir do |tmpdir|
        test_data = "Compression test data" * 50

        # Test Store (no compression)
        zip_path = File.join(tmpdir, "store.zip")
        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_data("file.txt", test_data)
        writer.write(compression_method: Omnizip::Formats::Zip::Constants::COMPRESSION_STORE)

        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        entry = reader.entries.first
        expect(entry.compression_method).to eq(Omnizip::Formats::Zip::Constants::COMPRESSION_STORE)
        expect(entry.compressed_size).to eq(test_data.bytesize)

        # Test Deflate
        zip_path = File.join(tmpdir, "deflate.zip")
        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_data("file.txt", test_data)
        writer.write(compression_method: Omnizip::Formats::Zip::Constants::COMPRESSION_DEFLATE)

        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        entry = reader.entries.first
        expect(entry.compression_method).to eq(Omnizip::Formats::Zip::Constants::COMPRESSION_DEFLATE)
        expect(entry.compressed_size).to be < test_data.bytesize
      end
    end
  end

  describe "CRC32 validation" do
    it "validates CRC32 checksums during extraction" do
      zip_path = File.join(fixtures_dir, "simple_deflate.zip")

      Dir.mktmpdir do |tmpdir|
        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

        # This should succeed with valid CRC
        expect {
          reader.extract_all(tmpdir)
        }.not_to raise_error
      end
    end

    it "calculates correct CRC32 when writing" do
      Dir.mktmpdir do |tmpdir|
        zip_path = File.join(tmpdir, "crc_test.zip")
        test_data = "CRC32 test data"

        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_data("test.txt", test_data)
        writer.write

        reader = Omnizip::Formats::Zip::Reader.new(zip_path).read
        entry = reader.entries.first

        # Calculate expected CRC
        expected_crc = Omnizip::Checksums::Crc32.new.tap { |c| c.update(test_data) }.finalize
        expect(entry.crc32).to eq(expected_crc)
      end
    end
  end

  describe "compatibility with standard tools" do
    it "creates files readable by Info-ZIP unzip" do
      Dir.mktmpdir do |tmpdir|
        zip_path = File.join(tmpdir, "compat.zip")

        writer = Omnizip::Formats::Zip::Writer.new(zip_path)
        writer.add_data("readme.txt", "Compatibility test\n")
        writer.write

        # Try to extract with system unzip
        output_dir = File.join(tmpdir, "unzipped")
        FileUtils.mkdir_p(output_dir)

        if system("which unzip > /dev/null 2>&1")
          result = system("unzip -q #{zip_path} -d #{output_dir}")
          expect(result).to be true
          expect(File.exist?(File.join(output_dir, "readme.txt"))).to be true
        end
      end
    end
  end

  describe "listing entries" do
    it "provides detailed entry information" do
      zip_path = File.join(fixtures_dir, "multi_file.zip")
      reader = Omnizip::Formats::Zip::Reader.new(zip_path).read

      entries = reader.list_entries
      expect(entries).to be_an(Array)
      expect(entries.size).to eq(2)

      entry = entries.first
      expect(entry).to have_key(:filename)
      expect(entry).to have_key(:compressed_size)
      expect(entry).to have_key(:uncompressed_size)
      expect(entry).to have_key(:compression_method)
      expect(entry).to have_key(:crc32)
      expect(entry).to have_key(:directory)
    end
  end

  describe "error handling" do
    it "raises error for non-existent file" do
      expect {
        Omnizip::Formats::Zip::Reader.new("nonexistent.zip").read
      }.to raise_error(Errno::ENOENT)
    end

    it "raises error for invalid ZIP file" do
      Dir.mktmpdir do |tmpdir|
        invalid_zip = File.join(tmpdir, "invalid.zip")
        File.write(invalid_zip, "Not a ZIP file")

        expect {
          Omnizip::Formats::Zip::Reader.new(invalid_zip).read
        }.to raise_error(Omnizip::FormatError)
      end
    end
  end

  describe "module-level API" do
    it "supports read through module" do
      zip_path = File.join(fixtures_dir, "simple_deflate.zip")
      reader = Omnizip::Formats::Zip.read(zip_path)

      expect(reader.entries.size).to eq(1)
    end

    it "supports create through module" do
      Dir.mktmpdir do |tmpdir|
        zip_path = File.join(tmpdir, "module_test.zip")

        writer = Omnizip::Formats::Zip.create(zip_path) do |zip|
          zip.add_data("file.txt", "Module API test")
        end
        writer.write

        expect(File.exist?(zip_path)).to be true
        reader = Omnizip::Formats::Zip.read(zip_path)
        expect(reader.entries.size).to eq(1)
      end
    end

    it "supports extract through module" do
      zip_path = File.join(fixtures_dir, "simple_deflate.zip")

      Dir.mktmpdir do |tmpdir|
        Omnizip::Formats::Zip.extract(zip_path, tmpdir)

        extracted_file = File.join(tmpdir, "hello.txt")
        expect(File.exist?(extracted_file)).to be true
      end
    end

    it "supports list through module" do
      zip_path = File.join(fixtures_dir, "multi_file.zip")
      entries = Omnizip::Formats::Zip.list(zip_path)

      expect(entries).to be_an(Array)
      expect(entries.size).to eq(2)
    end
  end
end