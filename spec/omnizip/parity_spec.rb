# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Parity do
  let(:temp_dir) { Dir.mktmpdir("omnizip_par2_test") }
  let(:test_file) { File.join(temp_dir, "test.dat") }
  let(:test_data) { "Hello, PAR2! " * 1000 } # ~14KB

  before do
    File.write(test_file, test_data)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".create" do
    it "creates PAR2 recovery files" do
      files = described_class.create(test_file, redundancy: 10)

      expect(files).not_to be_empty
      expect(files.first).to end_with(".par2")
      expect(File.exist?(files.first)).to be true
    end

    it "creates index and volume files" do
      files = described_class.create(test_file, redundancy: 5)

      # Should have at least index file
      index_file = files.find { |f| f.end_with?(".par2") && !f.include?("vol") }
      expect(index_file).not_to be_nil

      # Should have volume files
      volume_files = files.select { |f| f.include?("vol") }
      expect(volume_files).not_to be_empty
    end

    it "accepts custom block size" do
      files = described_class.create(test_file,
                                     redundancy: 5,
                                     block_size: 8192)

      expect(files).not_to be_empty
    end

    it "works with multiple files" do
      file2 = File.join(temp_dir, "test2.dat")
      File.write(file2, "Second file data" * 500)

      pattern = File.join(temp_dir, "*.dat")
      files = described_class.create(pattern, redundancy: 10)

      expect(files).not_to be_empty
    end

    it "supports custom output directory" do
      output_dir = File.join(temp_dir, "par2_output")
      files = described_class.create(test_file,
                                     redundancy: 5,
                                     output_dir: output_dir)

      files.each do |file|
        expect(file).to start_with(output_dir)
      end
    end

    it "raises error for nonexistent file" do
      expect do
        described_class.create("nonexistent.dat")
      end.to raise_error(ArgumentError, /No files match pattern/)
    end

    it "accepts progress callback" do
      progress_calls = []
      described_class.create(test_file,
                             redundancy: 5,
                             progress: ->(pct, msg) {
                               progress_calls << [pct, msg]
                             })

      expect(progress_calls).not_to be_empty
      expect(progress_calls.first[0]).to be_a(Integer)
      expect(progress_calls.first[1]).to be_a(String)
    end
  end

  describe ".verify" do
    let!(:par2_file) do
      files = described_class.create(test_file, redundancy: 10)
      files.find { |f| f.end_with?(".par2") && !f.include?("vol") }
    end

    it "verifies intact files" do
      result = described_class.verify(par2_file)

      expect(result).to be_a(Omnizip::Parity::Par2Verifier::VerificationResult)
      expect(result.all_ok?).to be true
      expect(result.damaged_files).to be_empty
      expect(result.missing_files).to be_empty
    end

    it "detects damaged files" do
      # Corrupt the file
      File.open(test_file, "r+b") do |io|
        io.seek(100)
        io.write("CORRUPTED")
      end

      result = described_class.verify(par2_file)

      expect(result.all_ok?).to be false
      expect(result.damaged_files).not_to be_empty
    end

    it "detects missing files" do
      File.delete(test_file)

      result = described_class.verify(par2_file)

      expect(result.all_ok?).to be false
      expect(result.missing_files).to include(File.basename(test_file))
    end

    it "indicates if damage is repairable" do
      # Small corruption should be repairable with 10% redundancy
      File.open(test_file, "r+b") do |io|
        io.seek(100)
        io.write("X")
      end

      result = described_class.verify(par2_file)

      expect(result.repairable?).to be true
    end
  end

  describe ".repair" do
    let!(:par2_file) do
      files = described_class.create(test_file, redundancy: 10)
      files.find { |f| f.end_with?(".par2") && !f.include?("vol") }
    end

    it "repairs damaged files" do
      # Corrupt the file
      File.open(test_file, "r+b") do |io|
        io.seek(100)
        io.write("CORRUPTED")
      end

      result = described_class.repair(par2_file)

      expect(result).to be_a(Omnizip::Parity::Par2Repairer::RepairResult)
      expect(result.success?).to be true
      expect(result.recovered_files).not_to be_empty
    end

    it "recovers missing files" do
      original_data = File.read(test_file)
      File.delete(test_file)

      result = described_class.repair(par2_file)

      expect(result.success?).to be true
      expect(File.exist?(test_file)).to be true

      # Verify recovered data matches original
      recovered_data = File.read(test_file)
      expect(recovered_data).to eq(original_data)
    end

    it "supports custom output directory" do
      output_dir = File.join(temp_dir, "recovered")
      File.delete(test_file)

      result = described_class.repair(par2_file, output_dir: output_dir)

      expect(result.success?).to be true
      recovered_file = File.join(output_dir, File.basename(test_file))
      expect(File.exist?(recovered_file)).to be true
    end

    it "fails when damage exceeds recovery capacity" do
      # Delete file and corrupt PAR2 (simulate excessive damage)
      File.delete(test_file)
      # Also delete some recovery volumes to reduce capacity
      Dir.glob(File.join(temp_dir, "*.vol*.par2")).each do |vol_file|
        File.delete(vol_file)
      end

      result = described_class.repair(par2_file)

      expect(result.success?).to be false
      expect(result.error_message).to include("Insufficient recovery blocks")
    end

    it "accepts progress callback" do
      File.open(test_file, "r+b") do |io|
        io.seek(100)
        io.write("X")
      end

      progress_calls = []
      described_class.repair(par2_file,
                             progress: ->(pct, msg) {
                               progress_calls << [pct, msg]
                             })

      expect(progress_calls).not_to be_empty
    end
  end

  describe ".protected?" do
    it "returns true if PAR2 files exist" do
      described_class.create(test_file, redundancy: 5)
      expect(described_class.protected?(test_file)).to be true
    end

    it "returns false if no PAR2 files" do
      expect(described_class.protected?(test_file)).to be false
    end
  end

  describe ".info" do
    it "returns protection information" do
      described_class.create(test_file, redundancy: 10, block_size: 8192)

      info = described_class.info(test_file)

      expect(info).to be_a(Hash)
      expect(info[:block_size]).to eq(8192)
      expect(info[:redundancy]).to be > 0
      expect(info[:par2_file]).to end_with(".par2")
    end

    it "returns nil for unprotected files" do
      info = described_class.info(test_file)
      expect(info).to be_nil
    end
  end

  describe "end-to-end workflow" do
    it "creates, verifies, damages, and repairs successfully" do
      # Step 1: Create PAR2 protection
      par2_files = described_class.create(test_file, redundancy: 15)
      expect(par2_files).not_to be_empty

      par2_index = par2_files.find { |f| !f.include?("vol") }

      # Step 2: Verify intact file
      result = described_class.verify(par2_index)
      expect(result.all_ok?).to be true

      # Step 3: Damage file
      original_data = File.read(test_file)
      File.open(test_file, "r+b") do |io|
        io.seek(1000)
        io.write("CORRUPTION" * 50)
      end

      # Step 4: Verify damaged file
      result = described_class.verify(par2_index)
      expect(result.all_ok?).to be false
      expect(result.repairable?).to be true

      # Step 5: Repair file
      repair_result = described_class.repair(par2_index)
      expect(repair_result.success?).to be true

      # Step 6: Verify repair
      result = described_class.verify(par2_index)
      expect(result.all_ok?).to be true

      # Step 7: Verify data matches original
      repaired_data = File.read(test_file)
      expect(repaired_data).to eq(original_data)
    end
  end
end
