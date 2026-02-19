# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "RAR5 Writer Integration" do
  let(:output_file) { Tempfile.new(["test", ".rar"]) }

  after { output_file.close! }

  describe "minimal empty archive" do
    it "creates valid empty archive" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.write

      # Verify file exists and is non-empty
      expect(File).to exist(output_file.path)
      expect(File.size(output_file.path)).to be > 8

      # Verify RAR5 signature
      sig = File.binread(output_file.path, 8)
      expect(sig).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")
    end

    it "has correct header structure" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.write

      data = File.binread(output_file.path)

      # RAR5 signature (8 bytes)
      expect(data[0..7]).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")

      # Main header follows signature
      # Byte 8: CRC32 (4 bytes)
      # Byte 12+: Header size (VINT), Type (VINT), Flags (VINT)
      expect(data.bytesize).to be >= 20 # Minimum: sig + main + end
    end
  end

  describe "archive with single file" do
    let(:test_file) { Tempfile.new("input.txt") }

    before do
      test_file.write("Hello, RAR5!")
      test_file.close
    end

    after { test_file.unlink }

    it "creates archive with file" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "hello.txt")
      writer.write

      # Verify archive created
      expect(File).to exist(output_file.path)
      expect(File.size(output_file.path)).to be > 50

      # Verify signature
      sig = File.binread(output_file.path, 8)
      expect(sig).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")
    end

    it "includes uncompressed file data" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "test.txt")
      writer.write

      data = File.binread(output_file.path)

      # File content should be present (STORE = uncompressed)
      expect(data).to include("Hello, RAR5!")
    end
  end

  describe "archive with multiple files" do
    let(:file1) { Tempfile.new("file1.txt") }
    let(:file2) { Tempfile.new("file2.txt") }

    before do
      file1.write("First file content")
      file1.close
      file2.write("Second file content")
      file2.close
    end

    after do
      file1.unlink
      file2.unlink
    end

    it "creates archive with multiple files" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(file1.path, "file1.txt")
      writer.add_file(file2.path, "file2.txt")
      writer.write

      expect(File).to exist(output_file.path)

      data = File.binread(output_file.path)
      expect(data).to include("First file content")
      expect(data).to include("Second file content")
    end
  end

  describe "unrar compatibility",
           skip: !system("which unrar > /dev/null 2>&1") do
    let(:test_file) { Tempfile.new("input.txt") }

    before do
      test_file.write("Test content for unrar")
      test_file.close
    end

    after { test_file.unlink }

    it "creates archive readable by unrar" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "test.txt")
      writer.write

      # Try to list with unrar
      output = `unrar l #{output_file.path} 2>&1`

      # Should not have errors
      expect(output).not_to include("corrupt")
      expect(output).not_to include("ERROR")
      expect(output).not_to include("Unexpected end of archive")

      # Should confirm RAR5 format
      expect(output).to include("Details: RAR 5")
    end

    it "unrar can list file entries" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "myfile.txt")
      writer.write

      output = `unrar l #{output_file.path} 2>&1`

      # Should list the file
      expect(output).to include("myfile.txt")
    end

    it "unrar can extract files" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "extract_test.txt")
      writer.write

      # Create temp extraction directory
      extract_dir = Dir.mktmpdir
      begin
        # Extract with unrar
        system("unrar x -o+ #{output_file.path} #{extract_dir}/ > /dev/null 2>&1")

        extracted_file = File.join(extract_dir, "extract_test.txt")
        expect(File).to exist(extracted_file)

        content = File.read(extracted_file)
        expect(content).to eq("Test content for unrar")
      ensure
        FileUtils.rm_rf(extract_dir)
      end
    end
  end
end
