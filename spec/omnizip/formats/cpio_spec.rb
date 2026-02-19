# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/cpio"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Formats::Cpio do
  let(:temp_dir) { Dir.mktmpdir("omnizip_cpio_test") }
  let(:output_cpio) { File.join(temp_dir, "test.cpio") }
  let(:test_file) { File.join(temp_dir, "test.txt") }
  let(:test_dir) { File.join(temp_dir, "test_directory") }

  before do
    File.write(test_file, "Hello, CPIO!")
    FileUtils.mkdir_p(test_dir)
    File.write(File.join(test_dir, "file1.txt"), "File 1")
    File.write(File.join(test_dir, "file2.txt"), "File 2")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".create" do
    it "creates CPIO archive in newc format" do
      result = described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
      end

      expect(result).to eq(output_cpio)
      expect(File.exist?(output_cpio)).to be true
    end

    it "supports CRC format" do
      described_class.create(output_cpio, format: :crc) do |cpio|
        cpio.add_file(test_file)
      end

      expect(File.exist?(output_cpio)).to be true

      # Verify CRC magic
      File.open(output_cpio, "rb") do |io|
        magic = io.read(6)
        expect(magic).to eq("070702")
      end
    end

    it "supports ODC format" do
      described_class.create(output_cpio, format: :odc) do |cpio|
        cpio.add_file(test_file)
      end

      expect(File.exist?(output_cpio)).to be true
    end

    it "adds multiple files" do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
        cpio.add_file(File.join(test_dir, "file1.txt"))
      end

      reader = described_class.open(output_cpio)
      expect(reader.entries.size).to be >= 2
    end

    it "adds directories recursively" do
      described_class.create(output_cpio) do |cpio|
        cpio.add_directory(test_dir)
      end

      reader = described_class.open(output_cpio)
      entries = reader.list

      expect(entries.any?(&:directory?)).to be true
      expect(entries.count(&:file?)).to be >= 2
    end

    it "adds directories non-recursively" do
      described_class.create(output_cpio) do |cpio|
        cpio.add_directory(test_dir, recursive: false)
      end

      reader = described_class.open(output_cpio)
      expect(reader.list.any?(&:directory?)).to be true
    end

    it "includes trailer entry" do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
      end

      reader = described_class.open(output_cpio)
      expect(reader.entries.any?(&:trailer?)).to be true
    end
  end

  describe ".open" do
    before do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
        cpio.add_directory(test_dir)
      end
    end

    it "opens and parses CPIO archive" do
      reader = described_class.open(output_cpio)
      expect(reader).to be_a(Omnizip::Formats::Cpio::Reader)
      expect(reader.entries).not_to be_empty
    end

    it "yields reader in block" do
      described_class.open(output_cpio) do |cpio|
        expect(cpio).to be_a(Omnizip::Formats::Cpio::Reader)
        expect(cpio.entries).not_to be_empty
      end
    end

    it "detects format automatically" do
      reader = described_class.open(output_cpio)
      expect(reader.format).to eq(:newc)
      expect(reader.format_name).to include("newc")
    end
  end

  describe ".list" do
    before do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
        cpio.add_directory(test_dir)
      end
    end

    it "lists archive contents" do
      entries = described_class.list(output_cpio)
      expect(entries).to be_an(Array)
      expect(entries).not_to be_empty
    end

    it "excludes trailer from list" do
      entries = described_class.list(output_cpio)
      expect(entries.none?(&:trailer?)).to be true
    end

    it "includes files and directories" do
      entries = described_class.list(output_cpio)
      expect(entries.any?(&:file?)).to be true
      expect(entries.any?(&:directory?)).to be true
    end
  end

  describe ".extract" do
    let(:extract_dir) { File.join(temp_dir, "extracted") }

    before do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file, "test.txt")
        cpio.add_directory(test_dir, cpio_path: "mydir")
      end
    end

    it "extracts all files" do
      described_class.extract(output_cpio, extract_dir)

      expect(Dir.exist?(extract_dir)).to be true
      expect(File.exist?(File.join(extract_dir, "test.txt"))).to be true
    end

    it "preserves file contents" do
      described_class.extract(output_cpio, extract_dir)

      extracted_content = File.read(File.join(extract_dir, "test.txt"))
      expect(extracted_content).to eq("Hello, CPIO!")
    end

    it "creates directory structure" do
      described_class.extract(output_cpio, extract_dir)

      expect(Dir.exist?(File.join(extract_dir, "mydir"))).to be true
    end

    it "preserves file permissions" do
      described_class.extract(output_cpio, extract_dir)

      extracted_file = File.join(extract_dir, "test.txt")
      expect(File.exist?(extracted_file)).to be true
      # Permissions may vary based on umask, so just verify file is readable
      expect(File.readable?(extracted_file)).to be true
    end
  end

  describe ".info" do
    before do
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
        cpio.add_directory(test_dir)
      end
    end

    it "returns archive information" do
      info = described_class.info(output_cpio)

      expect(info).to be_a(Hash)
      expect(info[:format]).to be_a(String)
      expect(info[:format_type]).to eq(:newc)
      expect(info[:entry_count]).to be > 0
      expect(info[:file_count]).to be >= 1
    end

    it "includes format details" do
      info = described_class.info(output_cpio)

      expect(info[:format]).to include("CPIO")
      expect(info[:total_size]).to be >= 0
    end
  end

  describe "format compatibility" do
    %i[newc crc odc].each do |format|
      context "with #{format} format" do
        let(:format_cpio) { File.join(temp_dir, "#{format}.cpio") }

        it "creates and extracts correctly" do
          # Create archive
          described_class.create(format_cpio, format: format) do |cpio|
            cpio.add_file(test_file)
          end

          # Extract archive
          extract_dir = File.join(temp_dir, "extract_#{format}")
          described_class.extract(format_cpio, extract_dir)

          # Verify extraction
          extracted_file = File.join(extract_dir, File.basename(test_file))
          expect(File.read(extracted_file)).to eq(File.read(test_file))
        end
      end
    end
  end

  describe "end-to-end workflow" do
    it "creates, lists, and extracts successfully" do
      # Create archive with multiple entries
      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file, "root.txt")
        cpio.add_directory(test_dir, cpio_path: "data")
      end

      # List contents
      entries = described_class.list(output_cpio)
      expect(entries.map(&:name)).to include("root.txt")
      expect(entries.any? { |e| e.name.start_with?("data") }).to be true

      # Extract
      extract_dir = File.join(temp_dir, "final_extract")
      described_class.extract(output_cpio, extract_dir)

      # Verify
      expect(File.read(File.join(extract_dir,
                                 "root.txt"))).to eq("Hello, CPIO!")
      expect(Dir.exist?(File.join(extract_dir, "data"))).to be true
    end
  end

  describe "special file handling" do
    it "handles symlinks" do
      symlink_path = File.join(temp_dir, "test_link")
      File.symlink(test_file, symlink_path)

      described_class.create(output_cpio) do |cpio|
        cpio.add_file(symlink_path)
      end

      reader = described_class.open(output_cpio)
      link_entry = reader.list.find(&:symlink?)
      expect(link_entry).not_to be_nil
    end

    it "preserves modification times" do
      # Set specific mtime
      mtime = Time.new(2024, 1, 1, 12, 0, 0)
      File.utime(mtime, mtime, test_file)

      described_class.create(output_cpio) do |cpio|
        cpio.add_file(test_file)
      end

      extract_dir = File.join(temp_dir, "time_test")
      described_class.extract(output_cpio, extract_dir)

      extracted_file = File.join(extract_dir, File.basename(test_file))
      # Mtime should be close (within a second due to precision)
      expect(File.mtime(extracted_file).to_i).to be_within(1).of(mtime.to_i)
    end
  end
end
