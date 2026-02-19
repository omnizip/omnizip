# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../../lib/omnizip/formats/rar/rar5/multi_volume/volume_splitter"

RSpec.describe Omnizip::Formats::Rar::Rar5::MultiVolume::VolumeSplitter do
  let(:max_volume_size) { 10_000 } # 10 KB for testing
  let(:splitter) { described_class.new(max_volume_size: max_volume_size) }

  describe "#initialize" do
    it "initializes with max volume size" do
      expect(splitter.max_volume_size).to eq(10_000)
      expect(splitter.current_volume_number).to eq(0)
      expect(splitter.current_volume_bytes).to eq(0)
      expect(splitter.volumes).to be_empty
    end
  end

  describe "#start_volume" do
    it "starts a new volume" do
      splitter.start_volume(1)

      expect(splitter.current_volume_number).to eq(1)
      expect(splitter.current_volume_bytes).to eq(described_class::HEADER_OVERHEAD)
    end

    it "resets data for each new volume" do
      splitter.start_volume(1)
      splitter.write_to_current_volume("test")
      splitter.start_volume(2)

      expect(splitter.current_volume_number).to eq(2)
      expect(splitter.current_volume_bytes).to eq(described_class::HEADER_OVERHEAD)
    end
  end

  describe "#can_fit_in_current_volume?" do
    before { splitter.start_volume(1) }

    it "returns true if data fits" do
      data_size = 1000

      expect(splitter.can_fit_in_current_volume?(data_size)).to be true
    end

    it "returns false if data doesn't fit" do
      data_size = max_volume_size # Exceeds remaining space

      expect(splitter.can_fit_in_current_volume?(data_size)).to be false
    end

    it "accounts for already written data" do
      splitter.write_to_current_volume("x" * 5000)

      # After writing 5000: 1024 (header) + 5000 = 6024 used
      # Remaining: 10000 - 6024 = 3976
      expect(splitter.can_fit_in_current_volume?(3000)).to be true
      expect(splitter.can_fit_in_current_volume?(4000)).to be false # Doesn't fit
    end
  end

  describe "#remaining_space" do
    before { splitter.start_volume(1) }

    it "returns remaining space in volume" do
      expected = max_volume_size - described_class::HEADER_OVERHEAD

      expect(splitter.remaining_space).to eq(expected)
    end

    it "decreases after writing data" do
      splitter.write_to_current_volume("x" * 1000)

      expected = max_volume_size - described_class::HEADER_OVERHEAD - 1000
      expect(splitter.remaining_space).to eq(expected)
    end
  end

  describe "#write_to_current_volume" do
    before { splitter.start_volume(1) }

    it "writes data to current volume" do
      data = "test data"

      expect { splitter.write_to_current_volume(data) }.not_to raise_error
      expect(splitter.current_volume_bytes).to eq(described_class::HEADER_OVERHEAD + data.bytesize)
    end

    it "raises error if no volume active" do
      splitter_no_vol = described_class.new(max_volume_size: max_volume_size)

      expect do
        splitter_no_vol.write_to_current_volume("test")
      end.to raise_error(/No active volume/)
    end

    it "raises error if data doesn't fit" do
      large_data = "x" * max_volume_size

      expect do
        splitter.write_to_current_volume(large_data)
      end.to raise_error(/doesn't fit/)
    end
  end

  describe "#finalize_volume" do
    before do
      splitter.start_volume(1)
      splitter.write_to_current_volume("test data")
    end

    it "finalizes current volume" do
      volume_info = splitter.finalize_volume

      expect(volume_info[:number]).to eq(1)
      expect(volume_info[:size]).to be > 0
      expect(volume_info[:data]).to eq("test data")
    end

    it "adds volume to volumes array" do
      splitter.finalize_volume

      expect(splitter.volumes.size).to eq(1)
      expect(splitter.volumes.first[:number]).to eq(1)
    end
  end

  describe "#calculate_file_distribution" do
    it "places single small file in one volume" do
      files = [
        { compressed_size: 1000, header_size: 100 },
      ]

      distribution = splitter.calculate_file_distribution(files)

      expect(distribution).to eq([[0]])
    end

    it "places multiple small files in one volume" do
      files = [
        { compressed_size: 1000, header_size: 100 },
        { compressed_size: 1000, header_size: 100 },
        { compressed_size: 1000, header_size: 100 },
      ]

      distribution = splitter.calculate_file_distribution(files)

      expect(distribution).to eq([[0, 1, 2]])
    end

    it "splits files across multiple volumes when needed" do
      files = [
        { compressed_size: 4000, header_size: 100 },
        { compressed_size: 4000, header_size: 100 },
        { compressed_size: 4000, header_size: 100 },
      ]

      distribution = splitter.calculate_file_distribution(files)

      # Each file is 4100 bytes (4000 + 100)
      # With 10,000 max volume and 1024 header overhead:
      # Volume 1 can fit: 1024 + 4100 + 4100 = 9224 < 10000 (2 files)
      # Volume 2 needs: 1024 + 4100 = 5124 < 10000 (1 file)
      expect(distribution.size).to eq(2)
      expect(distribution[0]).to eq([0, 1])
      expect(distribution[1]).to eq([2])
    end

    it "optimizes file placement" do
      files = [
        { compressed_size: 3000, header_size: 100 },
        { compressed_size: 3000, header_size: 100 },
        { compressed_size: 3000, header_size: 100 },
        { compressed_size: 3000, header_size: 100 },
      ]

      distribution = splitter.calculate_file_distribution(files)

      # Should fit 2 files per volume (2 * 3100 = 6200 < 10000)
      expect(distribution.size).to eq(2)
      expect(distribution[0]).to eq([0, 1])
      expect(distribution[1]).to eq([2, 3])
    end

    it "handles empty file list" do
      distribution = splitter.calculate_file_distribution([])

      expect(distribution).to eq([])
    end

    it "handles single very large file" do
      files = [
        { compressed_size: 20_000, header_size: 100 }, # Larger than max volume
      ]

      distribution = splitter.calculate_file_distribution(files)

      # File gets its own volume (spanning not implemented yet)
      expect(distribution).to eq([[0]])
    end
  end

  describe ".needs_splitting?" do
    it "returns true if total size exceeds max" do
      result = described_class.needs_splitting?(15_000, 10_000)

      expect(result).to be true
    end

    it "returns false if total size fits" do
      result = described_class.needs_splitting?(5_000, 10_000)

      expect(result).to be false
    end

    it "returns false if exactly equal" do
      result = described_class.needs_splitting?(10_000, 10_000)

      expect(result).to be false
    end
  end
end
