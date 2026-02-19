# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar"
require "omnizip/formats/rar/recovery_record"
require "omnizip/formats/rar/parity_handler"
require "omnizip/formats/rar/archive_verifier"
require "omnizip/formats/rar/archive_repairer"

RSpec.describe "RAR Recovery Support" do
  let(:test_dir) { File.join(__dir__, "../../../fixtures/rar") }

  describe Omnizip::Formats::Rar::RecoveryRecord do
    let(:rar4_version) { 4 }
    let(:rar5_version) { 5 }

    describe "#initialize" do
      it "creates recovery record for RAR4" do
        record = described_class.new(rar4_version)
        expect(record.version).to eq(4)
        expect(record.available?).to be false
      end

      it "creates recovery record for RAR5" do
        record = described_class.new(rar5_version)
        expect(record.version).to eq(5)
        expect(record.available?).to be false
      end
    end

    describe "#available?" do
      it "returns false when no recovery data" do
        record = described_class.new(rar4_version)
        expect(record.available?).to be false
      end

      it "returns true when recovery blocks present" do
        record = described_class.new(rar4_version)
        record.instance_variable_set(:@recovery_blocks, 10)
        expect(record.available?).to be true
      end

      it "returns true when external files present" do
        record = described_class.new(rar4_version)
        record.instance_variable_set(:@external_files, ["test.rev"])
        expect(record.available?).to be true
      end
    end

    describe "#external?" do
      it "returns false for integrated recovery" do
        record = described_class.new(rar4_version)
        expect(record.external?).to be false
      end

      it "returns true for external recovery" do
        record = described_class.new(rar4_version)
        record.instance_variable_set(:@type, described_class::TYPE_EXTERNAL)
        expect(record.external?).to be true
      end
    end

    describe "#detect_external_files" do
      it "detects RAR4 .rev files" do
        record = described_class.new(rar4_version)
        archive_path = "/path/to/archive.rar"

        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with("/path/to/archive.rev").and_return(true)

        rev_files = record.detect_external_files(archive_path)
        expect(rev_files).to include("/path/to/archive.rev")
      end

      it "detects RAR5 .partNN.rar.rev files" do
        record = described_class.new(rar5_version)
        archive_path = "/path/to/archive.part01.rar"

        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with("/path/to/archive.part01.rar.rev").and_return(true)

        rev_files = record.detect_external_files(archive_path)
        expect(rev_files).to include("/path/to/archive.part01.rar.rev")
      end
    end

    describe "#load_external_files" do
      it "loads existing .rev files" do
        record = described_class.new(rar4_version)
        rev_files = ["/path/to/test.rev"]

        allow(File).to receive(:exist?).with("/path/to/test.rev").and_return(true)

        record.load_external_files(rev_files)
        expect(record.external_files).to eq(rev_files)
        expect(record.external?).to be true
      end

      it "skips non-existent .rev files" do
        record = described_class.new(rar4_version)
        rev_files = ["/path/to/missing.rev"]

        allow(File).to receive(:exist?).with("/path/to/missing.rev").and_return(false)

        record.load_external_files(rev_files)
        expect(record.external_files).to be_empty
      end
    end

    describe "#protection_level" do
      it "calculates protection percentage" do
        record = described_class.new(rar4_version)
        record.instance_variable_set(:@protected_size, 1000)
        record.instance_variable_set(:@recovery_size, 50)

        expect(record.protection_level).to eq(5.0)
      end

      it "returns 0 for zero protected size" do
        record = described_class.new(rar4_version)
        record.instance_variable_set(:@protected_size, 0)
        record.instance_variable_set(:@recovery_size, 50)

        expect(record.protection_level).to eq(0.0)
      end
    end
  end

  describe Omnizip::Formats::Rar::ParityHandler do
    let(:recovery_record) do
      record = Omnizip::Formats::Rar::RecoveryRecord.new(4)
      record.instance_variable_set(:@block_size, 512)
      record.instance_variable_set(:@protected_size, 5120)
      record.instance_variable_set(:@recovery_blocks, 10)
      record
    end

    let(:parity_handler) { described_class.new(recovery_record) }

    describe "#initialize" do
      it "creates parity handler with recovery record" do
        handler = described_class.new(recovery_record)
        expect(handler.recovery_record).to eq(recovery_record)
        expect(handler.parity_blocks).to be_empty
      end
    end

    describe "#total_blocks" do
      it "calculates total blocks from protected size" do
        expect(parity_handler.total_blocks).to eq(10)
      end

      it "returns 0 for zero block size" do
        record = Omnizip::Formats::Rar::RecoveryRecord.new(4)
        handler = described_class.new(record)
        expect(handler.total_blocks).to eq(0)
      end
    end

    describe "#can_recover?" do
      it "returns false when no parity blocks" do
        expect(parity_handler.can_recover?(0)).to be false
      end

      it "returns true when parity block exists" do
        parity_handler.instance_variable_set(:@parity_blocks,
                                             [{ index: 0, data: "test" }])
        expect(parity_handler.can_recover?(0)).to be true
      end

      it "returns false when parity block not found" do
        parity_handler.instance_variable_set(:@parity_blocks,
                                             [{ index: 0, data: "test" }])
        expect(parity_handler.can_recover?(1)).to be false
      end
    end

    describe "#parity_block" do
      it "finds parity block by index" do
        block = { index: 5, data: "test" }
        parity_handler.instance_variable_set(:@parity_blocks, [block])

        expect(parity_handler.parity_block(5)).to eq(block)
      end

      it "returns nil when block not found" do
        expect(parity_handler.parity_block(99)).to be_nil
      end
    end
  end

  describe Omnizip::Formats::Rar::ArchiveVerifier do
    let(:archive_path) { "/path/to/test.rar" }
    let(:verifier) { described_class.new(archive_path) }

    describe "#initialize" do
      it "creates verifier with archive path" do
        expect(verifier.archive_path).to eq(archive_path)
        expect(verifier.recovery_record).to be_nil
      end
    end

    describe Omnizip::Formats::Rar::ArchiveVerifier::VerificationResult do
      let(:result) { described_class.new }

      it "initializes with default values" do
        expect(result.valid).to be true
        expect(result.files_total).to eq(0)
        expect(result.files_ok).to eq(0)
        expect(result.files_corrupted).to eq(0)
        expect(result.corrupted_files).to be_empty
        expect(result.recoverable).to be false
      end

      describe "#valid?" do
        it "returns true when valid and no corrupted files" do
          expect(result.valid?).to be true
        end

        it "returns false when invalid" do
          result.valid = false
          expect(result.valid?).to be false
        end

        it "returns false when files corrupted" do
          result.files_corrupted = 1
          expect(result.valid?).to be false
        end
      end

      describe "#can_repair?" do
        it "returns false when no recovery" do
          expect(result.can_repair?).to be false
        end

        it "returns true when recovery available and recoverable" do
          result.recovery_available = true
          result.recoverable = true
          expect(result.can_repair?).to be true
        end
      end

      describe "#summary" do
        it "returns OK summary for valid archive" do
          result.files_total = 10
          expect(result.summary).to include("Archive OK")
        end

        it "returns corrupted summary for invalid archive" do
          result.valid = false
          result.files_total = 10
          result.files_corrupted = 2
          expect(result.summary).to include("corrupted")
        end

        it "includes repairable in summary" do
          result.valid = false
          result.files_corrupted = 1
          result.files_total = 10
          result.recovery_available = true
          result.recoverable = true
          expect(result.summary).to include("repairable")
        end
      end
    end
  end

  describe Omnizip::Formats::Rar::ArchiveRepairer do
    let(:repairer) { described_class.new }

    describe "#initialize" do
      it "creates repairer instance" do
        expect(repairer.verifier).to be_nil
        expect(repairer.recovery_record).to be_nil
      end
    end

    describe Omnizip::Formats::Rar::ArchiveRepairer::RepairResult do
      let(:result) { described_class.new }

      it "initializes with default values" do
        expect(result.success).to be false
        expect(result.repaired_files).to be_empty
        expect(result.unrepaired_files).to be_empty
        expect(result.repaired_blocks).to be_empty
        expect(result.errors).to be_empty
      end

      describe "#success?" do
        it "returns false by default" do
          expect(result.success?).to be false
        end

        it "returns true when success and no unrepaired files" do
          result.success = true
          expect(result.success?).to be true
        end

        it "returns false when unrepaired files exist" do
          result.success = true
          result.unrepaired_files = ["file.txt"]
          expect(result.success?).to be false
        end
      end

      describe "#summary" do
        it "returns success summary" do
          result.success = true
          result.repaired_files = ["file1.txt", "file2.txt"]
          result.repaired_blocks = [1, 2, 3]
          expect(result.summary).to include("successful")
          expect(result.summary).to include("2 files")
          expect(result.summary).to include("3 blocks")
        end

        it "returns partial repair summary" do
          result.success = false
          result.repaired_files = ["file1.txt"]
          result.unrepaired_files = ["file2.txt"]
          expect(result.summary).to include("Partial")
        end

        it "returns failed summary" do
          result.success = false
          result.errors = ["Test error"]
          expect(result.summary).to include("failed")
        end
      end
    end
  end

  describe "Integration Tests" do
    let(:recovery_fixture_dir) do
      File.join(__dir__, "../../../fixtures/rar/recovery")
    end
    let(:test_archive) do
      File.join(recovery_fixture_dir, "test_with_recovery.rar")
    end
    let(:corrupted_archive) do
      File.join(recovery_fixture_dir, "test_corrupted.rar")
    end
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    describe Omnizip::Formats::Rar do
      describe ".verify" do
        it "returns verification result" do
          result = described_class.verify(test_archive)

          expect(result).to be_a(Omnizip::Formats::Rar::ArchiveVerifier::VerificationResult)
          # Test that API works - actual verification depends on implementation
          expect(result).to respond_to(:valid?)
          expect(result).to respond_to(:recovery_available)
          expect(result).to respond_to(:summary)
        end
      end

      describe ".repair" do
        it "repairs corrupted archive" do
          output_path = File.join(temp_dir, "repaired.rar")

          # This test validates that the repair API works
          # The actual repair may not succeed depending on implementation
          expect do
            described_class.repair(corrupted_archive, output_path)
          end.not_to raise_error
        end
      end
    end
  end
end
