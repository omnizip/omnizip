# frozen_string_literal: true

require "spec_helper"
require "omnizip/rubyzip_compat"
require "tmpdir"

RSpec.describe "Rubyzip Compatibility" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:zip_path) { File.join(tmpdir, "test.zip") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "Zip module" do
    it "exists as alias for Omnizip::Zip" do
      expect(defined?(Zip)).to be_truthy
    end

    it "has File class" do
      expect(Zip::File).to eq(Omnizip::Zip::File)
    end

    it "has Entry class" do
      expect(Zip::Entry).to eq(Omnizip::Zip::Entry)
    end

    it "has OutputStream class" do
      expect(Zip::OutputStream).to eq(Omnizip::Zip::OutputStream)
    end

    it "has InputStream class" do
      expect(Zip::InputStream).to eq(Omnizip::Zip::InputStream)
    end

    it "has error classes" do
      expect(Zip::Error).to eq(Omnizip::Error)
      expect(Zip::FormatError).to eq(Omnizip::FormatError)
      expect(Zip::CompressionError).to eq(Omnizip::CompressionError)
      expect(Zip::DecompressionError).to eq(Omnizip::DecompressionError)
      expect(Zip::ChecksumError).to eq(Omnizip::ChecksumError)
    end

    it "has VERSION constant" do
      expect(Zip::VERSION).to eq(Omnizip::VERSION)
    end
  end

  describe "Zip::File" do
    describe ".open" do
      it "creates a new ZIP file" do
        Zip::File.open(zip_path, create: true) do |zip|
          zip.add("test.txt") { "Hello World" }
        end

        expect(File.exist?(zip_path)).to be true
      end

      it "reads existing ZIP file" do
        # Create file first
        Zip::File.create(zip_path) do |zip|
          zip.add("file1.txt") { "Content 1" }
          zip.add("file2.txt") { "Content 2" }
        end

        # Read it
        Zip::File.open(zip_path) do |zip|
          expect(zip.entries.size).to eq(2)
          expect(zip.names).to contain_exactly("file1.txt", "file2.txt")
        end
      end

      it "works without block (manual close required)" do
        zip = Zip::File.open(zip_path, create: true)
        zip.add("test.txt") { "Test" }
        zip.close

        expect(File.exist?(zip_path)).to be true
      end
    end

    describe ".create" do
      it "creates new archive" do
        Zip::File.create(zip_path) do |zip|
          zip.add("readme.txt") { "README content" }
        end

        Zip::File.open(zip_path) do |zip|
          expect(zip.get_entry("readme.txt")).to be_truthy
        end
      end
    end

    describe "#add" do
      it "adds file from path" do
        source_file = File.join(tmpdir, "source.txt")
        File.write(source_file, "Source content")

        Zip::File.create(zip_path) do |zip|
          zip.add("added.txt", source_file)
        end

        Zip::File.open(zip_path) do |zip|
          content = zip.read("added.txt")
          expect(content).to eq("Source content")
        end
      end

      it "adds file from block" do
        Zip::File.create(zip_path) do |zip|
          zip.add("block.txt") { "Block content" }
        end

        Zip::File.open(zip_path) do |zip|
          content = zip.read("block.txt")
          expect(content).to eq("Block content")
        end
      end

      it "adds directory" do
        Zip::File.create(zip_path) do |zip|
          zip.add("subdir/")
        end

        Zip::File.open(zip_path) do |zip|
          entry = zip.get_entry("subdir/")
          expect(entry).to be_truthy
          expect(entry.directory?).to be true
        end
      end
    end

    describe "#each" do
      it "iterates over entries" do
        Zip::File.create(zip_path) do |zip|
          zip.add("file1.txt") { "1" }
          zip.add("file2.txt") { "2" }
          zip.add("file3.txt") { "3" }
        end

        names = []
        Zip::File.open(zip_path) do |zip|
          zip.each { |entry| names << entry.name }
        end

        expect(names).to contain_exactly("file1.txt", "file2.txt", "file3.txt")
      end
    end

    describe "#extract" do
      it "extracts file to destination" do
        Zip::File.create(zip_path) do |zip|
          zip.add("extract.txt") { "Extract me" }
        end

        dest_path = File.join(tmpdir, "extracted.txt")
        Zip::File.open(zip_path) do |zip|
          zip.extract("extract.txt", dest_path)
        end

        expect(File.read(dest_path)).to eq("Extract me")
      end

      it "handles overwrite callback" do
        # Create file that exists
        existing = File.join(tmpdir, "existing.txt")
        File.write(existing, "Old")

        Zip::File.create(zip_path) do |zip|
          zip.add("file.txt") { "New" }
        end

        Zip::File.open(zip_path) do |zip|
          zip.extract("file.txt", existing) { |entry, path| true }
        end

        expect(File.read(existing)).to eq("New")
      end
    end

    describe "#remove" do
      it "removes entry from archive" do
        Zip::File.create(zip_path) do |zip|
          zip.add("keep.txt") { "Keep" }
          zip.add("remove.txt") { "Remove" }
        end

        Zip::File.open(zip_path) do |zip|
          zip.remove("remove.txt")
        end

        Zip::File.open(zip_path) do |zip|
          expect(zip.include?("keep.txt")).to be true
          expect(zip.include?("remove.txt")).to be false
        end
      end
    end

    describe "#rename" do
      it "renames entry" do
        Zip::File.create(zip_path) do |zip|
          zip.add("old.txt") { "Content" }
        end

        Zip::File.open(zip_path) do |zip|
          zip.rename("old.txt", "new.txt")
        end

        Zip::File.open(zip_path) do |zip|
          expect(zip.include?("old.txt")).to be false
          expect(zip.include?("new.txt")).to be true
        end
      end
    end

    describe "#replace" do
      it "replaces entry content" do
        Zip::File.create(zip_path) do |zip|
          zip.add("file.txt") { "Old content" }
        end

        Zip::File.open(zip_path) do |zip|
          zip.replace("file.txt") { "New content" }
        end

        Zip::File.open(zip_path) do |zip|
          expect(zip.read("file.txt")).to eq("New content")
        end
      end
    end

    describe "#glob" do
      it "finds entries by pattern" do
        Zip::File.create(zip_path) do |zip|
          zip.add("test1.txt") { "1" }
          zip.add("test2.txt") { "2" }
          zip.add("other.dat") { "3" }
        end

        Zip::File.open(zip_path) do |zip|
          matches = zip.glob("*.txt")
          expect(matches.map(&:name)).to contain_exactly("test1.txt", "test2.txt")
        end
      end
    end
  end

  describe "Zip::OutputStream" do
    it "creates archive with streaming API" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("entry1.txt")
        zos.write("First entry")

        zos.put_next_entry("entry2.txt")
        zos.write("Second entry")
      end

      Zip::File.open(zip_path) do |zip|
        expect(zip.read("entry1.txt")).to eq("First entry")
        expect(zip.read("entry2.txt")).to eq("Second entry")
      end
    end

    it "supports << operator" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("test.txt")
        zos << "Part 1 "
        zos << "Part 2"
      end

      Zip::File.open(zip_path) do |zip|
        expect(zip.read("test.txt")).to eq("Part 1 Part 2")
      end
    end

    it "supports puts and print" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("puts.txt")
        zos.puts("Line 1", "Line 2")

        zos.put_next_entry("print.txt")
        zos.print("No", " newline")
      end

      Zip::File.open(zip_path) do |zip|
        expect(zip.read("puts.txt")).to eq("Line 1\nLine 2\n")
        expect(zip.read("print.txt")).to eq("No newline")
      end
    end

    it "creates directory entries" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("dir/")
        zos.put_next_entry("dir/file.txt")
        zos.write("In directory")
      end

      Zip::File.open(zip_path) do |zip|
        expect(zip.get_entry("dir/").directory?).to be true
        expect(zip.read("dir/file.txt")).to eq("In directory")
      end
    end
  end

  describe "Zip::InputStream" do
    it "reads archive with streaming API" do
      # Create test archive
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("file1.txt")
        zos.write("Content 1")
        zos.put_next_entry("file2.txt")
        zos.write("Content 2")
      end

      # Read it
      entries = []
      Zip::InputStream.open(zip_path) do |zis|
        while (entry = zis.get_next_entry)
          entries << {
            name: entry.name,
            content: zis.read,
          }
        end
      end

      expect(entries).to contain_exactly(
        { name: "file1.txt", content: "Content 1" },
        { name: "file2.txt", content: "Content 2" }
      )
    end

    it "supports partial reads" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("data.txt")
        zos.write("0123456789")
      end

      Zip::InputStream.open(zip_path) do |zis|
        entry = zis.get_next_entry
        expect(entry.name).to eq("data.txt")

        chunk1 = zis.read(5)
        chunk2 = zis.read(5)

        expect(chunk1).to eq("01234")
        expect(chunk2).to eq("56789")
      end
    end

    it "supports rewind" do
      Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("test.txt")
        zos.write("Test")
      end

      Zip::InputStream.open(zip_path) do |zis|
        zis.get_next_entry
        expect(zis.eof?).to be true

        zis.rewind
        entry = zis.get_next_entry
        expect(entry).to be_truthy
        expect(zis.eof?).to be false
      end
    end
  end

  describe "Real-world rubyzip code examples" do
    it "works with typical rubyzip creation pattern" do
      # This is actual rubyzip code that should work
      Zip::File.open(zip_path, create: true) do |zipfile|
        source = File.join(tmpdir, "readme.txt")
        File.write(source, "Documentation")
        zipfile.add("README.txt", source)

        zipfile.add("config.yml") do
          "production:\n  host: example.com"
        end
      end

      # Verify
      Zip::File.open(zip_path) do |zipfile|
        expect(zipfile.read("README.txt")).to eq("Documentation")
        expect(zipfile.read("config.yml")).to include("example.com")
      end
    end

    it "works with typical rubyzip extraction pattern" do
      # Create archive
      Zip::File.open(zip_path, create: true) do |zipfile|
        zipfile.add("file1.txt") { "File 1" }
        zipfile.add("dir/file2.txt") { "File 2" }
      end

      # Extract (typical rubyzip pattern)
      output_dir = File.join(tmpdir, "output")
      Zip::File.open(zip_path) do |zipfile|
        zipfile.each do |entry|
          fpath = File.join(output_dir, entry.name)
          FileUtils.mkdir_p(File.dirname(fpath))
          zipfile.extract(entry, fpath) { true }
        end
      end

      expect(File.read(File.join(output_dir, "file1.txt"))).to eq("File 1")
      expect(File.read(File.join(output_dir, "dir/file2.txt"))).to eq("File 2")
    end
  end
end