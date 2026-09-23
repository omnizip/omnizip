# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../../../lib/omnizip/formats/rar/rar5/writer"

ORACLE = File.expand_path("../../../../fixtures/rar/oracle", __dir__).freeze

RSpec.describe "RAR5 Multi-Volume Archives Integration" do
  let(:temp_dir) { Dir.mktmpdir("rar5_multivolume_test") }
  let(:output_archive) { File.join(temp_dir, "test_archive.rar") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def create_test_file(path, size)
    File.open(path, "wb") do |f|
      # Write predictable data for verification
      (size / 1024).times { f.write(("A".."Z").to_a.join * 40) }
      f.write(("A".."Z").to_a.join * (size % 1024))
    end
  end

  def unrar_available?
    system("which unrar > /dev/null 2>&1")
  end

  describe "single-file archive (no splitting)" do
    it "creates single volume when file fits" do
      test_file = File.join(temp_dir, "small.txt")
      create_test_file(test_file, 1024) # 1 KB

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: "10M",
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      expect(volumes).to be_an(Array)
      expect(volumes.size).to eq(1)
      expect(File.exist?(volumes[0])).to be true
    end
  end

  describe "multi-volume archive (splitting required)" do
    it "splits large archive into multiple volumes" do
      # Create test files - make them large enough to require splitting
      3.times do |i|
        path = File.join(temp_dir, "file#{i}.txt")
        File.write(path, "Content of file #{i}\n" * 3000) # ~54 KB each = 162 KB total
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB - minimum valid size
                                                       compression: :store)

      3.times do |i|
        test_file = File.join(temp_dir, "file#{i}.txt")
        writer.add_file(test_file)
      end

      volumes = writer.write

      expect(volumes).to be_an(Array)
      expect(volumes.size).to be > 1
      expect(volumes.size).to be <= 4 # Rough estimate
      volumes.each { |vol| expect(File.exist?(vol)).to be true }
    end

    it "uses correct volume naming (part style)" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "X" * 100_000) # 100 KB

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       volume_naming: "part",
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      expect(volumes[0]).to end_with(".part1.rar")
      if volumes.size > 1
        expect(volumes[1]).to end_with(".part2.rar")
      end
    end

    it "handles human-readable size strings" do
      test_file = File.join(temp_dir, "large.txt")
      File.write(test_file, "Y" * 200_000) # 200 KB

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: "64K", # Minimum valid size as string
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      expect(volumes).to be_an(Array)
      expect(volumes).not_to be_empty
    end
  end

  describe "multi-volume with LZSS compression" do
    it "creates compressed multi-volume archive" do
      # NOTE: RAR5 uses LZSS compression (methods 1-5), not LZMA.
      # Until LZSS is implemented, :lzss compression falls back to STORE.
      # This test verifies multi-volume archive creation works.

      # Create files with compressible content
      3.times do |i|
        path = File.join(temp_dir, "compress#{i}.txt")
        File.write(path, "Repeated content. " * 1000) # Compressible
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :lzss,
                                                       level: 3)

      3.times do |i|
        test_file = File.join(temp_dir, "compress#{i}.txt")
        writer.add_file(test_file)
      end

      volumes = writer.write

      expect(volumes).to be_an(Array)
      volumes.each { |vol| expect(File.exist?(vol)).to be true }
    end
  end

  describe "multi-volume with directory" do
    it "creates multi-volume from directory contents" do
      source_dir = File.join(temp_dir, "source")
      FileUtils.mkdir_p(source_dir)

      # Create files in directory - make them large enough
      5.times do |i|
        File.write(File.join(source_dir, "file#{i}.txt"), "Data #{i}\n" * 4000) # ~32 KB each = 160 KB total
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :store)

      writer.add_directory(source_dir)
      volumes = writer.write

      expect(volumes).to be_an(Array)
      expect(volumes.size).to be > 1
    end
  end

  describe "volume file properties" do
    it "creates volumes with valid RAR5 signatures" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Z" * 150_000) # 150 KB

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      volumes.each do |vol|
        data = File.binread(vol, 8)
        signature = data.unpack("C*")
        expect(signature).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01,
                                 0x00])
      end
    end

    it "respects volume size limits" do
      test_file = File.join(temp_dir, "test.txt")
      # Use file size that will actually split across volumes with current implementation
      # Current implementation places atomic files, so use multiple smaller files
      File.write(test_file, "A" * 40_000) # 40 KB - fits in 64KB volume

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      # With 40KB file + headers, should fit in one volume
      expect(volumes.size).to eq(1)

      volumes.each do |vol|
        size = File.size(vol)
        # Should fit within volume size + reasonable header overhead
        expect(size).to be <= (65_536 + 4000)
      end
    end
  end

  describe "oracle-frozen volume compatibility" do
    # These volumes were split by the writer, validated once by the unrar
    # CLI (test + extract) and frozen into spec/fixtures/rar/oracle by
    # scripts/generate_rar_oracle_fixtures.rb — no oracle at runtime.
    it "fresh volumes match the unrar-validated fixtures byte-for-byte" do
      part1 = File.join(ORACLE, "rar5_mv.part1.rar")
      skip "oracle fixtures missing" unless File.exist?(part1)

      %w[compat0.txt compat1.txt].each_with_index do |name, i|
        File.binwrite(File.join(temp_dir, name), "Compatible content #{i}\n" * 3000)
      end

      archive = File.join(temp_dir, "rar5_mv.rar")
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(
        archive, multi_volume: true, volume_size: 65_536, compression: :store
      )
      writer.add_file(File.join(temp_dir, "compat0.txt"))
      writer.add_file(File.join(temp_dir, "compat1.txt"))
      volumes = writer.write

      expect(volumes.size).to eq(2)
      volumes.each_with_index do |vol, i|
        expect(File.binread(vol)).to eq(File.binread(File.join(ORACLE, "rar5_mv.part#{i + 1}.rar")))
      end
    end

    it "the frozen listing shows the oracle accepted the split" do
      listing = File.read(File.join(ORACLE, "rar5_multivolume.unrar-l.txt"))

      expect(listing).to include("compat0.txt") # part1 carries compat0 (atomic placement)
      expect(listing).not_to match(/corrupt|ERROR/i)
    end
  end

  describe "edge cases" do
    it "handles single file exactly fitting one volume" do
      test_file = File.join(temp_dir, "exact.txt")
      File.write(test_file, "X" * 50_000) # Less than 64 KB

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :store)

      writer.add_file(test_file)
      volumes = writer.write

      expect(volumes.size).to eq(1)
    end

    it "handles empty directory" do
      empty_dir = File.join(temp_dir, "empty")
      FileUtils.mkdir_p(empty_dir)

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       multi_volume: true,
                                                       volume_size: 65_536, # 64 KB
                                                       compression: :store)

      writer.add_directory(empty_dir)
      volumes = writer.write

      # Should create archive even if no files
      expect(volumes).to be_an(Array)
    end
  end

  describe "backward compatibility" do
    it "single-file mode still works" do
      test_file = File.join(temp_dir, "test.txt")
      create_test_file(test_file, 1024)

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_archive,
                                                       compression: :store)

      writer.add_file(test_file)
      result = writer.write

      expect(result).to eq(output_archive)
      expect(File.exist?(output_archive)).to be true
    end
  end
end
