# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/seven_zip"
require "omnizip/models/split_options"
require "fileutils"
require "tmpdir"

RSpec.describe "SevenZip Split Archive Support" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_files_dir) { File.join(temp_dir, "test_files") }

  before do
    FileUtils.mkdir_p(test_files_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def create_test_file(name, size_kb)
    path = File.join(test_files_dir, name)
    File.binwrite(path, "A" * (size_kb * 1024))
    path
  end

  def create_test_files(count, size_kb_each)
    count.times.map { |i| create_test_file("file#{i}.txt", size_kb_each) }
  end

  describe Omnizip::Models::SplitOptions do
    describe "#parse_volume_size" do
      it "parses kilobytes" do
        expect(described_class.parse_volume_size("100K")).to eq(100 * 1024)
        expect(described_class.parse_volume_size("50KB")).to eq(50 * 1024)
      end

      it "parses megabytes" do
        expect(described_class.parse_volume_size("100M")).to eq(100 * 1024 * 1024)
        expect(described_class.parse_volume_size("50MB")).to eq(50 * 1024 * 1024)
      end

      it "parses gigabytes" do
        expect(described_class.parse_volume_size("2G")).to eq(2 * 1024 * 1024 * 1024)
        expect(described_class.parse_volume_size("4.7GB")).to eq((4.7 * 1024 * 1024 * 1024).to_i)
      end

      it "handles integers" do
        expect(described_class.parse_volume_size(1024)).to eq(1024)
      end

      it "handles plain numbers" do
        expect(described_class.parse_volume_size("1024")).to eq(1024)
      end
    end

    describe "#volume_filename" do
      let(:options) { described_class.new }

      context "with numeric naming" do
        before { options.naming_pattern = Omnizip::Models::SplitOptions::NAMING_NUMERIC }

        it "generates correct volume filenames" do
          expect(options.volume_filename("backup.7z.001", 1)).to eq("backup.7z.001")
          expect(options.volume_filename("backup.7z.001", 2)).to eq("backup.7z.002")
          expect(options.volume_filename("backup.7z.001", 10)).to eq("backup.7z.010")
        end
      end

      context "with alpha naming" do
        before { options.naming_pattern = Omnizip::Models::SplitOptions::NAMING_ALPHA }

        it "generates correct volume filenames" do
          expect(options.volume_filename("backup.7z.aa", 1)).to eq("backup.7z.aa")
          expect(options.volume_filename("backup.7z.aa", 2)).to eq("backup.7z.ab")
          expect(options.volume_filename("backup.7z.aa", 26)).to eq("backup.7z.az")
          expect(options.volume_filename("backup.7z.aa", 27)).to eq("backup.7z.ba")
        end
      end
    end

    describe "#validate!" do
      let(:options) { described_class.new }

      it "validates positive volume_size" do
        options.volume_size = -1
        expect { options.validate! }.to raise_error(ArgumentError, /volume_size must be positive/)
      end

      it "validates naming_pattern" do
        options.naming_pattern = :invalid
        expect { options.validate! }.to raise_error(ArgumentError, /naming_pattern must be one of/)
      end

      it "validates span_strategy" do
        options.span_strategy = :invalid
        expect { options.validate! }.to raise_error(ArgumentError, /span_strategy must be one of/)
      end

      it "passes with valid options" do
        expect { options.validate! }.not_to raise_error
      end
    end
  end

  describe "Split Archive Creation" do
    let(:volume_size) { 50 * 1024 } # 50 KB per volume
    let(:split_options) do
      Omnizip::Models::SplitOptions.new.tap do |opts|
        opts.volume_size = volume_size
      end
    end

    it "creates split archives" do
      create_test_files(3, 40) # 3 files x 40KB each = 120KB total
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      Dir.glob(File.join(test_files_dir, "*")).each do |file|
        writer.add_file(file)
      end

      writer.write

      # Should create multiple volumes
      expect(File.exist?(File.join(temp_dir, "archive.7z.001"))).to be true
      expect(File.exist?(File.join(temp_dir, "archive.7z.002"))).to be true

      # Check volumes are within size limit (allowing for overhead)
      volume1_size = File.size(File.join(temp_dir, "archive.7z.001"))
      expect(volume1_size).to be <= volume_size
    end

    it "handles files larger than volume size" do
      create_test_file("large.txt", 80) # 80KB file
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      writer.add_file(File.join(test_files_dir, "large.txt"))
      writer.write

      # Should create at least one volume
      expect(File.exist?(File.join(temp_dir, "archive.7z.001"))).to be true
    end

    it "creates single volume for small archives" do
      create_test_file("small.txt", 5) # 5KB file
      archive_path = File.join(temp_dir, "archive.7z.001")

      large_volume_size = 100 * 1024 # 100KB
      opts = Omnizip::Models::SplitOptions.new
      opts.volume_size = large_volume_size

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        opts
      )

      writer.add_file(File.join(test_files_dir, "small.txt"))
      writer.write

      # Should only create one volume
      expect(File.exist?(File.join(temp_dir, "archive.7z.001"))).to be true
      expect(File.exist?(File.join(temp_dir, "archive.7z.002"))).to be false
    end
  end

  describe "Split Archive Reading" do
    let(:volume_size) { 50 * 1024 } # 50 KB per volume
    let(:split_options) do
      Omnizip::Models::SplitOptions.new.tap do |opts|
        opts.volume_size = volume_size
      end
    end

    it "reads split archives" do
      # Create split archive
      test_files = create_test_files(3, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      # Read split archive
      reader = Omnizip::Formats::SevenZip::SplitArchiveReader.new(archive_path)
      reader.open

      expect(reader.split?).to be true
      expect(reader.total_volumes).to be >= 2
      expect(reader.entries.size).to eq(3)
    end

    it "auto-detects volumes" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      reader = Omnizip::Formats::SevenZip::SplitArchiveReader.new(archive_path)
      reader.open

      volumes = reader.volumes
      expect(volumes).to include(archive_path)
      expect(volumes.size).to be >= 1
    end

    it "extracts files from split archives" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      # Extract
      extract_dir = File.join(temp_dir, "extracted")
      reader = Omnizip::Formats::SevenZip::SplitArchiveReader.new(archive_path)
      reader.open
      reader.extract_all(extract_dir)
      reader.close

      # Verify extracted files
      expect(File.exist?(File.join(extract_dir, "file0.txt"))).to be true
      expect(File.exist?(File.join(extract_dir, "file1.txt"))).to be true

      # Verify content
      original_content = File.binread(test_files[0])
      extracted_content = File.binread(File.join(extract_dir, "file0.txt"))
      expect(extracted_content).to eq(original_content)
    end
  end

  describe "Reader Integration" do
    let(:volume_size) { 50 * 1024 }

    it "detects split archives" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      split_options = Omnizip::Models::SplitOptions.new
      split_options.volume_size = volume_size

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      # Use main Reader class
      reader = Omnizip::Formats::SevenZip::Reader.new(archive_path)
      reader.open

      expect(reader.split?).to be true
      expect(reader.total_volumes).to be >= 2
    end

    it "reads non-split archives normally" do
      test_file = create_test_file("test.txt", 5)
      archive_path = File.join(temp_dir, "archive.7z")

      writer = Omnizip::Formats::SevenZip::Writer.new(
        archive_path,
        algorithm: :lzma2,
        level: 1
      )

      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::SevenZip::Reader.new(archive_path)
      reader.open

      expect(reader.split?).to be false
      expect(reader.total_volumes).to eq(1)
    end
  end

  describe "Writer Integration" do
    it "creates split archive via Writer with volume_size option" do
      test_files = create_test_files(3, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      writer = Omnizip::Formats::SevenZip::Writer.new(
        archive_path,
        algorithm: :lzma2,
        level: 1,
        volume_size: 50 * 1024
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      expect(File.exist?(File.join(temp_dir, "archive.7z.001"))).to be true
      expect(File.exist?(File.join(temp_dir, "archive.7z.002"))).to be true
    end
  end

  describe "Edge Cases" do
    it "handles missing volumes gracefully" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      split_options = Omnizip::Models::SplitOptions.new
      split_options.volume_size = 50 * 1024

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      test_files.each { |file| writer.add_file(file) }
      writer.write

      # Delete second volume
      volume2 = File.join(temp_dir, "archive.7z.002")
      FileUtils.rm(volume2) if File.exist?(volume2)

      reader = Omnizip::Formats::SevenZip::SplitArchiveReader.new(archive_path)
      reader.open

      # Should only detect remaining volumes
      expect(reader.volumes).not_to include(volume2)
    end

    it "handles empty archive" do
      archive_path = File.join(temp_dir, "empty.7z.001")

      split_options = Omnizip::Models::SplitOptions.new
      split_options.volume_size = 50 * 1024

      writer = Omnizip::Formats::SevenZip::SplitArchiveWriter.new(
        archive_path,
        { algorithm: :lzma2, level: 1 },
        split_options
      )

      writer.write

      expect(File.exist?(archive_path)).to be true
    end
  end

  describe "Module-level API" do
    it "creates split archives using SevenZip.create_split" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      split_options = Omnizip::Models::SplitOptions.new
      split_options.volume_size = 50 * 1024

      Omnizip::Formats::SevenZip.create_split(
        archive_path,
        split_options,
        algorithm: :lzma2,
        level: 1
      ) do |writer|
        test_files.each { |file| writer.add_file(file) }
      end

      expect(File.exist?(archive_path)).to be true
    end

    it "opens split archives using SevenZip.open" do
      test_files = create_test_files(2, 40)
      archive_path = File.join(temp_dir, "archive.7z.001")

      split_options = Omnizip::Models::SplitOptions.new
      split_options.volume_size = 50 * 1024

      Omnizip::Formats::SevenZip.create_split(
        archive_path,
        split_options,
        algorithm: :lzma2,
        level: 1
      ) do |writer|
        test_files.each { |file| writer.add_file(file) }
      end

      Omnizip::Formats::SevenZip.open(archive_path) do |reader|
        expect(reader.split?).to be true
        expect(reader.entries.size).to eq(2)
      end
    end
  end
end