# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/par2_verifier"
require "omnizip/parity/par2_repairer"
require "digest"

RSpec.describe "PAR2 Compatibility Tests" do
  # Helper method to get fixture path
  def fixture_path(relative_path)
    File.join(__dir__, "../../fixtures/par2cmdline/flatdata-par2files",
              relative_path)
  end

  describe "test2: Basic PAR2 Verification" do
    it "verifies pre-generated PAR2 files correctly" do
      par2_file = fixture_path("testdata.par2")

      # Ensure fixture exists
      expect(File.exist?(par2_file)).to be true

      # Create verifier
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)

      # Verify
      result = verifier.verify

      # Check results
      expect(result.all_ok?).to be true
      expect(result.damaged_files).to be_empty
      expect(result.damaged_blocks).to be_empty
      expect(result.missing_files).to be_empty
    end

    it "reports correct file count and block information" do
      par2_file = fixture_path("testdata.par2")
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)

      result = verifier.verify

      # Should have 10 data files (test-0.data through test-9.data)
      expect(result.total_blocks).to be > 0

      # Should have recovery blocks available
      expect(result.recovery_blocks).to be > 0
    end

    it "identifies all data files in the PAR2 archive" do
      par2_file = fixture_path("testdata.par2")
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)

      # Access file list through verification
      result = verifier.verify

      # Verify all test files are present and intact
      (0..9).each do |i|
        data_file = fixture_path("test-#{i}.data")
        expect(File.exist?(data_file)).to be true
      end

      expect(result.all_ok?).to be true
    end
  end

  describe "test4: Simple Repair (2 deleted files)" do
    it "repairs 2 deleted files using PAR2 recovery" do
      # Use temp directory for isolated testing
      Dir.mktmpdir("par2_repair_test") do |temp_dir|
        # Copy all fixture files to temp directory
        par2_file = File.join(temp_dir, "testdata.par2")
        FileUtils.cp(fixture_path("testdata.par2"), par2_file)

        # Copy all recovery volumes
        Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
          FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
        end

        # Copy all data files and store original checksums
        original_checksums = {}
        (0..9).each do |i|
          filename = "test-#{i}.data"
          source = fixture_path(filename)
          dest = File.join(temp_dir, filename)
          FileUtils.cp(source, dest)

          # Store original checksum for later verification
          original_checksums[filename] = Digest::MD5.file(dest).hexdigest
        end

        # Delete test-0.data and test-1.data
        FileUtils.rm(File.join(temp_dir, "test-0.data"))
        FileUtils.rm(File.join(temp_dir, "test-1.data"))

        # Verify damage is detected
        verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
        result_before = verifier.verify

        expect(result_before.all_ok?).to be false
        expect(result_before.missing_files).to include("test-0.data",
                                                       "test-1.data")
        expect(result_before.repairable?).to be true

        # Perform repair
        repairer = Omnizip::Parity::Par2Repairer.new(par2_file)
        repair_result = repairer.repair

        # Check repair was successful
        expect(repair_result.success?).to be true
        expect(repair_result.recovered_files).to include("test-0.data",
                                                         "test-1.data")
        expect(repair_result.recovered_blocks).to be > 0
        expect(repair_result.unrecoverable).to be_empty

        # Verify repaired files exist
        expect(File.exist?(File.join(temp_dir, "test-0.data"))).to be true
        expect(File.exist?(File.join(temp_dir, "test-1.data"))).to be true

        # Verify repaired files match originals (checksum verification)
        repaired_checksum_0 = Digest::MD5.file(File.join(temp_dir,
                                                         "test-0.data")).hexdigest
        repaired_checksum_1 = Digest::MD5.file(File.join(temp_dir,
                                                         "test-1.data")).hexdigest

        expect(repaired_checksum_0).to eq(original_checksums["test-0.data"])
        expect(repaired_checksum_1).to eq(original_checksums["test-1.data"])

        # Verify all files pass verification after repair
        result_after = verifier.verify
        expect(result_after.all_ok?).to be true
        expect(result_after.damaged_files).to be_empty
        expect(result_after.missing_files).to be_empty
      end
    end
  end

  describe "test5: Full Recovery (100% redundancy)" do
    it "recovers all files from PAR2 when all data files deleted" do
      # Use the 100% redundancy fixture
      par2_file_name = "testdata_100pct.par2"
      par2_file = fixture_path(par2_file_name)

      # Skip if 100% fixture doesn't exist yet
      unless File.exist?(par2_file)
        skip "100% redundancy fixture not available. Run: par2 create -s5376 -r100 testdata_100pct.par2 test-*.data"
      end

      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
      result = verifier.verify

      # Verify we have 100% redundancy
      redundancy_pct = (result.recovery_blocks.to_f / result.total_blocks * 100).round(1)
      expect(redundancy_pct).to eq(100.0)

      # Use temp directory for isolated testing
      Dir.mktmpdir("par2_full_recovery_test") do |temp_dir|
        # Copy PAR2 files to temp directory
        temp_par2 = File.join(temp_dir, par2_file_name)
        FileUtils.cp(par2_file, temp_par2)

        # Copy all recovery volumes
        Dir.glob(fixture_path("testdata_100pct.vol*.par2")).each do |vol_file|
          FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
        end

        # Copy all data files and store original checksums
        original_checksums = {}
        (0..9).each do |i|
          filename = "test-#{i}.data"
          source = fixture_path(filename)
          dest = File.join(temp_dir, filename)
          FileUtils.cp(source, dest)

          # Store original checksum for later verification
          original_checksums[filename] = Digest::MD5.file(dest).hexdigest

          # Delete ALL data files
          FileUtils.rm(File.join(temp_dir, "test-#{i}.data"))
        end

        # Verify all files are detected as missing
        verifier = Omnizip::Parity::Par2Verifier.new(temp_par2)
        result_before = verifier.verify

        expect(result_before.all_ok?).to be false
        (0..9).each do |i|
          expect(result_before.missing_files).to include("test-#{i}.data")
        end
        expect(result_before.repairable?).to be true

        # Perform repair
        repairer = Omnizip::Parity::Par2Repairer.new(temp_par2)
        repair_result = repairer.repair

        # Check repair was successful
        unless repair_result.success?
          puts "Repair failed: #{repair_result.error_message}"
        end
        expect(repair_result.success?).to be true
        (0..9).each do |i|
          expect(repair_result.recovered_files).to include("test-#{i}.data")
        end
        expect(repair_result.unrecoverable).to be_empty

        # Verify all files exist
        (0..9).each do |i|
          expect(File.exist?(File.join(temp_dir, "test-#{i}.data"))).to be true

          # Verify all recovered files match originals (checksum verification)
          filename = "test-#{i}.data"
          recovered_checksum = Digest::MD5.file(File.join(temp_dir,
                                                          filename)).hexdigest
          expect(recovered_checksum).to eq(original_checksums[filename])
        end

        # Verify all files pass verification after repair
        result_after = verifier.verify
        expect(result_after.all_ok?).to be true
        expect(result_after.damaged_files).to be_empty
        expect(result_after.missing_files).to be_empty
      end
    end
  end

  # Phase 3: Advanced Verification Tests

  describe "test3.1: Detection of Missing Files" do
    context "when files are deleted from protected set" do
      it "detects all missing files correctly" do
        Dir.mktmpdir("par2_missing_test") do |temp_dir|
          # Copy PAR2 files
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          # Copy only some data files (simulate missing files)
          (2..9).each do |i|
            FileUtils.cp(fixture_path("test-#{i}.data"),
                         File.join(temp_dir, "test-#{i}.data"))
          end

          # Verify detects the 2 missing files
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.missing_files).to include("test-0.data")
          expect(result.missing_files).to include("test-1.data")
          expect(result.missing_files.size).to eq(2)
          expect(result.repairable?).to be true
        end
      end
    end

    context "when all files are missing" do
      it "detects all files as missing" do
        Dir.mktmpdir("par2_all_missing_test") do |temp_dir|
          # Copy only PAR2 files (no data files)
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          # Verify detects all 10 files as missing
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.missing_files.size).to eq(10)
          (0..9).each do |i|
            expect(result.missing_files).to include("test-#{i}.data")
          end
        end
      end
    end
  end

  describe "test3.2: Detection of Corrupted Data" do
    context "when file data is corrupted" do
      it "detects corrupted blocks in modified file" do
        Dir.mktmpdir("par2_corruption_test") do |temp_dir|
          # Copy all files
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          (0..9).each do |i|
            FileUtils.cp(fixture_path("test-#{i}.data"),
                         File.join(temp_dir, "test-#{i}.data"))
          end

          # Corrupt one file by modifying its content
          corrupted_file = File.join(temp_dir, "test-0.data")
          original_content = File.binread(corrupted_file)
          # Flip some bits in the middle of the file
          corrupted_content = original_content.dup
          corrupted_content[original_content.size / 2] =
            (corrupted_content[original_content.size / 2].ord ^ 0xFF).chr
          File.binwrite(corrupted_file, corrupted_content)

          # Verify detects corruption
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.damaged_files).to include("test-0.data")
          expect(result.damaged_files.size).to be >= 1
          expect(result.missing_files).to be_empty
        end
      end
    end

    context "when multiple files are corrupted" do
      it "detects all corrupted files" do
        Dir.mktmpdir("par2_multi_corruption_test") do |temp_dir|
          # Copy all files
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          (0..9).each do |i|
            FileUtils.cp(fixture_path("test-#{i}.data"),
                         File.join(temp_dir, "test-#{i}.data"))
          end

          # Corrupt multiple files
          [0, 1, 5].each do |i|
            corrupted_file = File.join(temp_dir, "test-#{i}.data")
            content = File.binread(corrupted_file)
            # Modify content
            modified_content = content.dup
            modified_content[content.size / 2] =
              (modified_content[content.size / 2].ord ^ 0xFF).chr
            File.binwrite(corrupted_file, modified_content)
          end

          # Verify detects all corruptions
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.damaged_files.size).to eq(3)
          expect(result.damaged_files).to include("test-0.data")
          expect(result.damaged_files).to include("test-1.data")
          expect(result.damaged_files).to include("test-5.data")
        end
      end
    end
  end

  describe "test3.3: Multi-Volume PAR2 Handling" do
    it "reads metadata from multi-volume PAR2 archives" do
      par2_file = fixture_path("testdata.par2")

      # Check that recovery volumes exist
      vol_files = Dir.glob(fixture_path("testdata.vol*.par2"))
      expect(vol_files).not_to be_empty

      # Verify can read main PAR2 file
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
      result = verifier.verify

      # Should successfully read even with split volumes
      expect(result.total_blocks).to be > 0
      expect(result.recovery_blocks).to be > 0
      expect(result.all_ok?).to be true
    end

    it "verifies files using recovery volumes" do
      Dir.mktmpdir("par2_multivolume_test") do |temp_dir|
        # Copy main PAR2 and ALL recovery volumes
        par2_file = File.join(temp_dir, "testdata.par2")
        FileUtils.cp(fixture_path("testdata.par2"), par2_file)

        vol_count = 0
        Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
          FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          vol_count += 1
        end

        expect(vol_count).to be > 0

        # Copy data files
        (0..9).each do |i|
          FileUtils.cp(fixture_path("test-#{i}.data"),
                       File.join(temp_dir, "test-#{i}.data"))
        end

        # Verify with all volumes present
        verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
        result = verifier.verify

        expect(result.all_ok?).to be true
        expect(result.recovery_blocks).to be > 0
      end
    end
  end

  describe "test3.4: Block Size Handling" do
    it "correctly identifies block size from PAR2 metadata" do
      par2_file = fixture_path("testdata.par2")
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)

      # Must call verify first to parse PAR2 file and populate metadata
      verifier.verify

      # Access metadata through verifier
      block_size = verifier.metadata[:block_size]

      expect(block_size).to be_a(Integer)
      expect(block_size).to be > 0
      expect(block_size).to be < 1_000_000 # Sanity check

      # Common block sizes are powers of 2
      # Allow some flexibility but should be reasonable
      expect(block_size).to be >= 512
      expect(block_size).to be <= 65536
    end

    it "calculates correct number of blocks for files" do
      par2_file = fixture_path("testdata.par2")
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
      result = verifier.verify

      # Total blocks should be positive and reasonable
      expect(result.total_blocks).to be > 0
      expect(result.total_blocks).to be < 10000 # Sanity check for small test files

      # Recovery blocks should be non-zero (redundancy present)
      expect(result.recovery_blocks).to be > 0
    end
  end

  describe "test3.5: File Size Verification" do
    context "when file size is modified" do
      it "detects size mismatch" do
        Dir.mktmpdir("par2_size_test") do |temp_dir|
          # Copy all files
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          (0..9).each do |i|
            FileUtils.cp(fixture_path("test-#{i}.data"),
                         File.join(temp_dir, "test-#{i}.data"))
          end

          # Truncate one file
          truncated_file = File.join(temp_dir, "test-0.data")
          original_content = File.binread(truncated_file)
          # Cut file in half
          File.binwrite(truncated_file,
                        original_content[0...(original_content.size / 2)])

          # Verify detects the truncation
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.damaged_files).to include("test-0.data")
        end
      end
    end

    context "when file size is expanded" do
      it "detects size mismatch with expanded file" do
        Dir.mktmpdir("par2_expanded_test") do |temp_dir|
          # Copy all files
          par2_file = File.join(temp_dir, "testdata.par2")
          FileUtils.cp(fixture_path("testdata.par2"), par2_file)

          Dir.glob(fixture_path("testdata.vol*.par2")).each do |vol_file|
            FileUtils.cp(vol_file, File.join(temp_dir, File.basename(vol_file)))
          end

          (0..9).each do |i|
            FileUtils.cp(fixture_path("test-#{i}.data"),
                         File.join(temp_dir, "test-#{i}.data"))
          end

          # Expand one file by appending data
          expanded_file = File.join(temp_dir, "test-0.data")
          File.open(expanded_file, "ab") do |f|
            f.write("EXTRA DATA" * 100)
          end

          # Verify detects the expansion
          verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
          result = verifier.verify

          expect(result.all_ok?).to be false
          expect(result.damaged_files).to include("test-0.data")
        end
      end
    end
  end
end
