# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/par2_creator"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Parity::Par2Creator do
  describe "integration with new ReedSolomonEncoder" do
    let(:temp_dir) { Dir.mktmpdir("par2_creator_test") }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "creates PAR2 files successfully" do
      # Create test file
      test_file = File.join(temp_dir, "test.dat")
      File.write(test_file, "A" * 1024) # 1KB file

      # Create PAR2 with new encoder
      creator = described_class.new(
        redundancy: 10,
        block_size: 512,
      )
      creator.add_file(test_file)

      base_name = File.join(temp_dir, "test")
      par2_files = creator.create(base_name)

      # Verify files were created
      expect(par2_files).not_to be_empty
      expect(File.exist?("#{base_name}.par2")).to be true

      # Verify main PAR2 file has content
      main_par2 = File.binread("#{base_name}.par2")
      expect(main_par2).to start_with("PAR2\x00PKT")
    end

    it "creates recovery volumes with correct structure" do
      # Create test file with known content
      test_file = File.join(temp_dir, "data.bin")
      test_data = (0..255).to_a.pack("C*") * 4 # 1KB repeating pattern
      File.write(test_file, test_data)

      # Create PAR2
      creator = described_class.new(
        redundancy: 20,
        block_size: 256,
      )
      creator.add_file(test_file)

      base_name = File.join(temp_dir, "data")
      par2_files = creator.create(base_name)

      # Should have main file + volume files
      expect(par2_files.size).to be > 1

      # Verify volume files exist
      volume_files = par2_files.select { |f| f.include?(".vol") }
      expect(volume_files).not_to be_empty

      # Each volume file should have PAR2 signature
      volume_files.each do |vol_file|
        content = File.binread(vol_file)
        expect(content).to start_with("PAR2\x00PKT")
      end
    end

    it "handles multiple files" do
      # Create multiple test files
      file1 = File.join(temp_dir, "file1.dat")
      file2 = File.join(temp_dir, "file2.dat")
      File.write(file1, "X" * 512)
      File.write(file2, "Y" * 768)

      # Create PAR2 protecting both files
      creator = described_class.new(
        redundancy: 15,
        block_size: 256,
      )
      creator.add_file(file1)
      creator.add_file(file2)

      base_name = File.join(temp_dir, "multi")
      par2_files = creator.create(base_name)

      expect(par2_files).not_to be_empty
      expect(File.exist?("#{base_name}.par2")).to be true
    end

    it "works with small block size" do
      test_file = File.join(temp_dir, "small.dat")
      File.write(test_file, "TEST" * 64) # 256 bytes

      creator = described_class.new(
        redundancy: 25,
        block_size: 128, # Small blocks
      )
      creator.add_file(test_file)

      base_name = File.join(temp_dir, "small")

      expect do
        par2_files = creator.create(base_name)
        expect(par2_files).not_to be_empty
      end.not_to raise_error
    end

    it "works with large block size" do
      test_file = File.join(temp_dir, "large.dat")
      File.write(test_file, "DATA" * 2048) # 8KB

      creator = described_class.new(
        redundancy: 10,
        block_size: 4096, # Large blocks
      )
      creator.add_file(test_file)

      base_name = File.join(temp_dir, "large")

      expect do
        par2_files = creator.create(base_name)
        expect(par2_files).not_to be_empty
      end.not_to raise_error
    end
  end
end
