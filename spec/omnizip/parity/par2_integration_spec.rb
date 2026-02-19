# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/par2_creator"
require "omnizip/parity/par2_verifier"
require "omnizip/parity/par2_repairer"
require "tempfile"
require "fileutils"

RSpec.describe "PAR2 Integration" do
  let(:temp_dir) { Dir.mktmpdir("par2_test") }
  let(:test_content1) { "Hello World! " * 100 }  # ~1.3KB
  let(:test_content2) { "Test Data ABC" * 100 }  # ~1.3KB
  let(:test_content3) { "123456789012" * 100 }   # ~1.2KB

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def create_test_file(name, content)
    path = File.join(temp_dir, name)
    File.write(path, content)
    path
  end

  describe "complete PAR2 workflow" do
    let(:file1) { create_test_file("test1.txt", test_content1) }
    let(:file2) { create_test_file("test2.txt", test_content2) }
    let(:file3) { create_test_file("test3.txt", test_content3) }
    let(:par2_base) { File.join(temp_dir, "backup") }

    context "PAR2 Creator" do
      it "creates PAR2 files with 10% redundancy" do
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 10,
          block_size: 1024,
        )

        creator.add_file(file1)
        creator.add_file(file2)
        creator.add_file(file3)

        par2_files = creator.create(par2_base)

        expect(par2_files).not_to be_empty
        expect(par2_files.first).to eq("#{par2_base}.par2")
        expect(File.exist?(par2_files.first)).to be true

        # Should also create volume files
        volume_files = par2_files[1..]
        expect(volume_files.size).to be > 0
        volume_files.each do |vol_file|
          expect(File.exist?(vol_file)).to be true
          expect(vol_file).to match(/\.vol\d+\+\d+\.par2$/)
        end
      end

      it "creates PAR2 files with custom block size" do
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 5,
          block_size: 512,
        )

        creator.add_file(file1)
        par2_files = creator.create(par2_base)

        expect(par2_files).not_to be_empty
        expect(File.exist?(par2_files.first)).to be true
      end

      it "raises error when no files added" do
        creator = Omnizip::Parity::Par2Creator.new(redundancy: 10)

        expect do
          creator.create(par2_base)
        end.to raise_error(/No files added/)
      end

      it "raises error for non-existent file" do
        creator = Omnizip::Parity::Par2Creator.new(redundancy: 10)

        expect do
          creator.add_file("/nonexistent/file.txt")
        end.to raise_error(ArgumentError, /File not found/)
      end

      it "reports progress via callback" do
        progress_calls = []
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 10,
          block_size: 1024,
          progress: ->(pct, msg) { progress_calls << [pct, msg] },
        )

        creator.add_file(file1)
        creator.create(par2_base)

        expect(progress_calls).not_to be_empty
        expect(progress_calls.first[0]).to eq(0)
        expect(progress_calls.last[0]).to eq(100)
      end
    end

    context "PAR2 Verifier" do
      before do
        # Create PAR2 files first
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 10,
          block_size: 1024,
        )
        creator.add_file(file1)
        creator.add_file(file2)
        creator.add_file(file3)
        @par2_files = creator.create(par2_base)
      end

      it "verifies intact files successfully" do
        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result = verifier.verify

        expect(result.all_ok?).to be true
        expect(result.damaged_files).to be_empty
        expect(result.missing_files).to be_empty
        expect(result.damaged_blocks).to be_empty
      end

      it "detects corrupted file" do
        # Corrupt file1
        File.write(file1, "CORRUPTED DATA" * 100)

        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result = verifier.verify

        expect(result.all_ok?).to be false
        expect(result.damaged_files).to include("test1.txt")
        expect(result.damaged_blocks).not_to be_empty
      end

      it "detects missing file" do
        # Delete file2
        File.delete(file2)

        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result = verifier.verify

        expect(result.all_ok?).to be false
        expect(result.missing_files).to include("test2.txt")
      end

      it "reports repairability correctly" do
        # Corrupt one small file (should be repairable with 10% redundancy)
        File.write(file1, "CORRUPTED" * 10)

        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result = verifier.verify

        expect(result.repairable?).to be true
        expect(result.recovery_blocks).to be > 0
      end

      it "detects unrepairable damage" do
        # Corrupt all files (exceeds 10% redundancy)
        File.write(file1, "CORRUPTED1" * 100)
        File.write(file2, "CORRUPTED2" * 100)
        File.write(file3, "CORRUPTED3" * 100)

        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result = verifier.verify

        expect(result.repairable?).to be false
      end

      it "raises error for missing PAR2 file" do
        expect do
          Omnizip::Parity::Par2Verifier.new("/nonexistent.par2")
        end.to raise_error(ArgumentError, /PAR2 file not found/)
      end
    end

    context "PAR2 Repairer" do
      let(:original_content1) { test_content1.dup }
      let(:original_content2) { test_content2.dup }
      let(:original_content3) { test_content3.dup }

      before do
        # Create PAR2 files with sufficient redundancy
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 70, # Sufficient for 4-block repair (was 50%)
          block_size: 1024,
        )
        creator.add_file(file1)
        creator.add_file(file2)
        creator.add_file(file3)
        @par2_files = creator.create(par2_base)
      end

      it "reports success when no repair needed" do
        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair

        expect(result.success?).to be true
        expect(result.recovered_files).to be_empty
        expect(result.recovered_blocks).to eq(0)
        expect(result.error_message).to be_nil
      end

      it "repairs single corrupted file" do
        # Corrupt file1
        File.write(file1, "CORRUPTED DATA" * 100)

        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair

        expect(result.success?).to be true
        expect(result.recovered_files).to include("test1.txt")
        expect(result.recovered_blocks).to be > 0

        # Verify file was restored correctly
        restored_content = File.read(file1)
        expect(restored_content).to eq(original_content1)
      end

      it "repairs missing file" do
        # Delete file2
        File.delete(file2)

        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair

        expect(result.success?).to be true
        expect(result.recovered_files).to include("test2.txt")
        expect(File.exist?(file2)).to be true

        # Verify restored content
        restored_content = File.read(file2)
        expect(restored_content).to eq(original_content2)
      end

      it "repairs multiple files" do
        # Corrupt two files
        File.write(file1, "CORRUPT1" * 100)
        File.write(file3, "CORRUPT3" * 100)

        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair

        expect(result.success?).to be true
        expect(result.recovered_files).to include("test1.txt", "test3.txt")

        # Verify both files restored
        expect(File.read(file1)).to eq(original_content1)
        expect(File.read(file3)).to eq(original_content3)
      end

      it "reports failure when damage exceeds redundancy" do
        # Corrupt all files severely
        File.write(file1, "X" * 5000)
        File.write(file2, "Y" * 5000)
        File.write(file3, "Z" * 5000)

        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair

        expect(result.success?).to be false
        expect(result.has_unrecoverable?).to be true
        expect(result.error_message).to match(/Insufficient recovery blocks|Singular matrix/)
      end

      it "writes repaired files to custom output directory" do
        output_dir = File.join(temp_dir, "repaired")
        File.write(file1, "CORRUPTED" * 100)

        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        result = repairer.repair(output_dir: output_dir)

        expect(result.success?).to be true

        repaired_file = File.join(output_dir, "test1.txt")
        expect(File.exist?(repaired_file)).to be true
        expect(File.read(repaired_file)).to eq(original_content1)
      end

      it "reports progress via callback" do
        progress_calls = []
        File.write(file1, "CORRUPTED" * 100)

        repairer = Omnizip::Parity::Par2Repairer.new(
          "#{par2_base}.par2",
          progress: ->(pct, msg) { progress_calls << [pct, msg] },
        )
        repairer.repair

        expect(progress_calls).not_to be_empty
        expect(progress_calls.first[0]).to eq(0)
        expect(progress_calls.last[0]).to eq(100)
      end
    end

    context "end-to-end recovery scenario" do
      it "creates, verifies, corrupts, and repairs files" do
        # Step 1: Create files and PAR2 protection
        creator = Omnizip::Parity::Par2Creator.new(
          redundancy: 50, # Sufficient for multi-block repair
          block_size: 1024,
        )
        creator.add_file(file1)
        creator.add_file(file2)
        par2_files = creator.create(par2_base)
        expect(par2_files).not_to be_empty

        # Step 2: Verify all OK
        verifier = Omnizip::Parity::Par2Verifier.new("#{par2_base}.par2")
        result1 = verifier.verify
        expect(result1.all_ok?).to be true

        # Step 3: Simulate corruption
        corrupted_content = "CORRUPTED DATA" * 100
        File.write(file1, corrupted_content)

        # Step 4: Verify detects corruption
        result2 = verifier.verify
        expect(result2.all_ok?).to be false
        expect(result2.damaged_files).to include("test1.txt")
        expect(result2.repairable?).to be true

        # Step 5: Repair the damage
        repairer = Omnizip::Parity::Par2Repairer.new("#{par2_base}.par2")
        repair_result = repairer.repair
        expect(repair_result.success?).to be true

        # Step 6: Verify repair was successful
        result3 = verifier.verify
        expect(result3.all_ok?).to be true

        # Verify content matches original
        expect(File.read(file1)).to eq(test_content1)
      end
    end
  end
end
