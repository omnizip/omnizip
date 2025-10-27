# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Native Omnizip API" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:zip_path) { File.join(tmpdir, "test.zip") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "Omnizip.compress_file" do
    it "compresses a single file" do
      source = File.join(tmpdir, "source.txt")
      File.write(source, "Test content for compression")

      result = Omnizip.compress_file(source, zip_path)

      expect(result).to eq(zip_path)
      expect(File.exist?(zip_path)).to be true

      # Verify content
      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.entries.size).to eq(1)
        expect(zip.read("source.txt")).to eq("Test content for compression")
      end
    end

    it "raises error for non-existent file" do
      expect {
        Omnizip.compress_file("nonexistent.txt", zip_path)
      }.to raise_error(Errno::ENOENT, /Input file not found/)
    end

    it "raises error for directory input" do
      dir = File.join(tmpdir, "testdir")
      FileUtils.mkdir_p(dir)

      expect {
        Omnizip.compress_file(dir, zip_path)
      }.to raise_error(ArgumentError, /Input is a directory/)
    end
  end

  describe "Omnizip.compress_directory" do
    it "compresses a directory" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "file1.txt"), "Content 1")
      File.write(File.join(source_dir, "file2.txt"), "Content 2")

      result = Omnizip.compress_directory(source_dir, zip_path)

      expect(result).to eq(zip_path)
      expect(File.exist?(zip_path)).to be true

      # Verify content
      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.entries.size).to eq(2)
        expect(zip.read("file1.txt")).to eq("Content 1")
        expect(zip.read("file2.txt")).to eq("Content 2")
      end
    end

    it "compresses directory recursively" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(File.join(source_dir, "subdir"))
      File.write(File.join(source_dir, "root.txt"), "Root")
      File.write(File.join(source_dir, "subdir", "sub.txt"), "Sub")

      Omnizip.compress_directory(source_dir, zip_path, recursive: true)

      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.include?("root.txt")).to be true
        expect(zip.include?("subdir/")).to be true
        expect(zip.include?("subdir/sub.txt")).to be true
      end
    end

    it "compresses only top level when not recursive" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(File.join(source_dir, "subdir"))
      File.write(File.join(source_dir, "root.txt"), "Root")
      File.write(File.join(source_dir, "subdir", "sub.txt"), "Sub")

      Omnizip.compress_directory(source_dir, zip_path, recursive: false)

      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.include?("root.txt")).to be true
        expect(zip.include?("subdir/")).to be true
        expect(zip.include?("subdir/sub.txt")).to be false
      end
    end

    it "raises error for non-existent directory" do
      expect {
        Omnizip.compress_directory("nonexistent_dir", zip_path)
      }.to raise_error(Errno::ENOENT)
    end

    it "raises error for file input" do
      file = File.join(tmpdir, "file.txt")
      File.write(file, "Not a directory")

      expect {
        Omnizip.compress_directory(file, zip_path)
      }.to raise_error(ArgumentError, /not a directory/)
    end
  end

  describe "Omnizip.extract_archive" do
    it "extracts archive to directory" do
      # Create archive
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("file1.txt") { "Content 1" }
        zip.add("file2.txt") { "Content 2" }
        zip.add("dir/")
        zip.add("dir/file3.txt") { "Content 3" }
      end

      output_dir = File.join(tmpdir, "output")
      files = Omnizip.extract_archive(zip_path, output_dir)

      expect(files.size).to eq(4)
      expect(File.read(File.join(output_dir, "file1.txt"))).to eq("Content 1")
      expect(File.read(File.join(output_dir, "file2.txt"))).to eq("Content 2")
      expect(File.read(File.join(output_dir, "dir/file3.txt"))).to eq("Content 3")
    end

    it "overwrites files when overwrite is true" do
      # Create archive
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("file.txt") { "New content" }
      end

      output_dir = File.join(tmpdir, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "file.txt"), "Old content")

      Omnizip.extract_archive(zip_path, output_dir, overwrite: true)

      expect(File.read(File.join(output_dir, "file.txt"))).to eq("New content")
    end

    it "raises error when file exists and overwrite is false" do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("file.txt") { "Content" }
      end

      output_dir = File.join(tmpdir, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "file.txt"), "Existing")

      expect {
        Omnizip.extract_archive(zip_path, output_dir, overwrite: false)
      }.to raise_error(/File exists/)
    end

    it "raises error for non-existent archive" do
      expect {
        Omnizip.extract_archive("nonexistent.zip", tmpdir)
      }.to raise_error(Errno::ENOENT)
    end
  end

  describe "Omnizip.list_archive" do
    before do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("file1.txt") { "Content 1" }
        zip.add("file2.txt") { "Content 2" }
        zip.add("dir/")
      end
    end

    it "lists entry names by default" do
      names = Omnizip.list_archive(zip_path)

      expect(names).to be_an(Array)
      expect(names).to contain_exactly("file1.txt", "file2.txt", "dir/")
    end

    it "returns detailed information when details is true" do
      details = Omnizip.list_archive(zip_path, details: true)

      expect(details).to be_an(Array)
      expect(details.size).to eq(3)

      file_entry = details.find { |e| e[:name] == "file1.txt" }
      expect(file_entry).to include(
        :name,
        :size,
        :compressed_size,
        :compression_method,
        :crc,
        :time,
        :directory
      )
      expect(file_entry[:directory]).to be false

      dir_entry = details.find { |e| e[:name] == "dir/" }
      expect(dir_entry[:directory]).to be true
    end

    it "raises error for non-existent archive" do
      expect {
        Omnizip.list_archive("nonexistent.zip")
      }.to raise_error(Errno::ENOENT)
    end
  end

  describe "Omnizip.read_from_archive" do
    before do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("config.yml") { "production:\n  host: example.com" }
        zip.add("readme.txt") { "Documentation" }
      end
    end

    it "reads file from archive" do
      content = Omnizip.read_from_archive(zip_path, "config.yml")

      expect(content).to eq("production:\n  host: example.com")
    end

    it "raises error for non-existent entry" do
      expect {
        Omnizip.read_from_archive(zip_path, "nonexistent.txt")
      }.to raise_error(Errno::ENOENT, /Entry not found/)
    end

    it "raises error for non-existent archive" do
      expect {
        Omnizip.read_from_archive("nonexistent.zip", "file.txt")
      }.to raise_error(Errno::ENOENT, /Archive not found/)
    end
  end

  describe "Omnizip.add_to_archive" do
    it "adds file to existing archive" do
      # Create initial archive
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("existing.txt") { "Existing" }
      end

      # Add new file
      source = File.join(tmpdir, "new.txt")
      File.write(source, "New content")

      result = Omnizip.add_to_archive(zip_path, "added.txt", source)

      expect(result).to eq(zip_path)

      # Verify both files exist
      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.include?("existing.txt")).to be true
        expect(zip.include?("added.txt")).to be true
        expect(zip.read("added.txt")).to eq("New content")
      end
    end

    it "raises error for non-existent archive" do
      source = File.join(tmpdir, "file.txt")
      File.write(source, "Content")

      expect {
        Omnizip.add_to_archive("nonexistent.zip", "file.txt", source)
      }.to raise_error(Errno::ENOENT, /Archive not found/)
    end

    it "raises error for non-existent source file" do
      Omnizip::Zip::File.create(zip_path) { |z| z.add("test.txt") { "Test" } }

      expect {
        Omnizip.add_to_archive(zip_path, "new.txt", "nonexistent.txt")
      }.to raise_error(Errno::ENOENT, /Source file not found/)
    end
  end

  describe "Omnizip.remove_from_archive" do
    it "removes file from archive" do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("keep.txt") { "Keep" }
        zip.add("remove.txt") { "Remove" }
      end

      result = Omnizip.remove_from_archive(zip_path, "remove.txt")

      expect(result).to eq(zip_path)

      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip.include?("keep.txt")).to be true
        expect(zip.include?("remove.txt")).to be false
      end
    end

    it "raises error for non-existent archive" do
      expect {
        Omnizip.remove_from_archive("nonexistent.zip", "file.txt")
      }.to raise_error(Errno::ENOENT)
    end
  end

  describe "Native API with Omnizip::Zip namespace" do
    it "provides full control with Omnizip::Zip::File" do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("test.txt") { "Test" }
      end

      Omnizip::Zip::File.open(zip_path) do |zip|
        expect(zip).to be_a(Omnizip::Zip::File)
        expect(zip.entries.first).to be_a(Omnizip::Zip::Entry)
      end
    end

    it "provides streaming with Omnizip::Zip::OutputStream" do
      Omnizip::Zip::OutputStream.open(zip_path) do |zos|
        expect(zos).to be_a(Omnizip::Zip::OutputStream)
        zos.put_next_entry("stream.txt")
        zos.write("Streamed content")
      end

      content = Omnizip.read_from_archive(zip_path, "stream.txt")
      expect(content).to eq("Streamed content")
    end

    it "provides streaming with Omnizip::Zip::InputStream" do
      Omnizip::Zip::File.create(zip_path) do |zip|
        zip.add("file.txt") { "Content" }
      end

      Omnizip::Zip::InputStream.open(zip_path) do |zis|
        expect(zis).to be_a(Omnizip::Zip::InputStream)
        entry = zis.get_next_entry
        expect(entry.name).to eq("file.txt")
        expect(zis.read).to eq("Content")
      end
    end
  end

  describe "Integration: Both APIs work together" do
    it "can use both native and compat APIs on same archive" do
      # Create with native API
      Omnizip.compress_file(
        File.join(tmpdir, "test.txt").tap { |f| File.write(f, "Test") },
        zip_path
      )

      # Read with both APIs
      native_content = Omnizip.read_from_archive(zip_path, "test.txt")

      require "omnizip/rubyzip_compat"
      compat_content = Zip::File.open(zip_path) { |z| z.read("test.txt") }

      expect(native_content).to eq(compat_content)
      expect(native_content).to eq("Test")
    end

    it "maintains compatibility between APIs" do
      require "omnizip/rubyzip_compat"

      # Create with compat API
      Zip::File.create(zip_path) do |zip|
        zip.add("compat.txt") { "Created with compat" }
      end

      # Modify with native API
      source = File.join(tmpdir, "native.txt")
      File.write(source, "Added with native")
      Omnizip.add_to_archive(zip_path, "native.txt", source)

      # Verify both entries exist with both APIs
      Zip::File.open(zip_path) do |zip|
        expect(zip.include?("compat.txt")).to be true
        expect(zip.include?("native.txt")).to be true
      end

      names = Omnizip.list_archive(zip_path)
      expect(names).to contain_exactly("compat.txt", "native.txt")
    end
  end

  describe "Error handling consistency" do
    it "raises Omnizip::Error subclasses" do
      expect(Omnizip::Error).to be < StandardError
      expect(Omnizip::FormatError).to be < Omnizip::Error
      expect(Omnizip::CompressionError).to be < Omnizip::Error
      expect(Omnizip::DecompressionError).to be < Omnizip::Error
    end

    it "provides same errors through both APIs" do
      require "omnizip/rubyzip_compat"

      expect(Zip::Error).to eq(Omnizip::Error)
      expect(Zip::FormatError).to eq(Omnizip::FormatError)
    end
  end
end