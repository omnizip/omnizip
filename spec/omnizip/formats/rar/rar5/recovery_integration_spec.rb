# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/writer"
require "tempfile"
require "tmpdir"

RSpec.describe "RAR5 Recovery (PAR2) Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:archive_path) { File.join(temp_dir, "archive.rar") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "PAR2 recovery file generation" do
    it "generates PAR2 files for RAR archive" do
      test_file = File.join(temp_dir, "data.txt")
      File.write(test_file, "Important data")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :store,
                                                       recovery: true,
                                                       recovery_percent: 10)

      writer.add_file(test_file)
      result = writer.write

      # Should return array with archive + PAR2 files
      expect(result).to be_an(Array)
      expect(result.size).to be >= 2 # Archive + at least index.par2

      # Check archive exists
      expect(File.exist?(archive_path)).to be true

      # Check PAR2 index file exists
      par2_index = archive_path.sub(".rar", ".par2")
      expect(result).to include(par2_index)
      expect(File.exist?(par2_index)).to be true
    end

    it "generates PAR2 with custom redundancy" do
      test_file = File.join(temp_dir, "test.dat")
      File.write(test_file, "X" * 10000)

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       recovery: true,
                                                       recovery_percent: 20) # 20% redundancy

      writer.add_file(test_file)
      result = writer.write

      expect(result).to be_an(Array)
      expect(result.size).to be >= 2
    end

    it "returns single path when recovery disabled" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       recovery: false)

      writer.add_file(test_file)
      result = writer.write

      # Should return single string path
      expect(result).to be_a(String)
      expect(result).to eq(archive_path)
    end
  end

  describe "PAR2 with multi-volume archives" do
    it "generates PAR2 for all volumes" do
      # Create files that will span multiple volumes
      3.times do |i|
        path = File.join(temp_dir, "file#{i}.dat")
        File.write(path, "Data #{i}" * 1000)
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       multi_volume: true,
                                                       volume_size: "64K",
                                                       recovery: true,
                                                       recovery_percent: 5)

      Dir.glob(File.join(temp_dir, "file*.dat")).each do |file|
        writer.add_file(file)
      end

      result = writer.write

      expect(result).to be_an(Array)
      # Should have volumes + PAR2 files
      expect(result.size).to be > 2
    end
  end

  describe "PAR2 with encryption" do
    it "generates PAR2 for encrypted archive" do
      test_file = File.join(temp_dir, "secret.txt")
      File.write(test_file, "Confidential")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       password: "TestPass123",
                                                       recovery: true,
                                                       recovery_percent: 10)

      writer.add_file(test_file)
      result = writer.write

      expect(result).to be_an(Array)
      expect(result.size).to be >= 2
    end
  end

  describe "PAR2 file format" do
    it "creates valid PAR2 packet structure" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test content")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       recovery: true,
                                                       recovery_percent: 5)

      writer.add_file(test_file)
      result = writer.write

      par2_index = result.find do |f|
        f.end_with?(".par2") && !f.include?("vol")
      end
      expect(par2_index).not_to be_nil

      # Check PAR2 signature
      signature = File.binread(par2_index, 8)
      expect(signature).to eq("PAR2\x00PKT".b)
    end
  end
end
