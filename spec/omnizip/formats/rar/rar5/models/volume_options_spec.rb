# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../../lib/omnizip/formats/rar/rar5/models/volume_options"

RSpec.describe Omnizip::Formats::Rar::Rar5::Models::VolumeOptions do
  describe "#initialize" do
    it "creates with default values" do
      options = described_class.new

      expect(options.max_volume_size).to eq(104_857_600) # 100 MB
      expect(options.volume_naming).to eq("part")
    end

    it "creates with custom values" do
      options = described_class.new(
        max_volume_size: 10_485_760,
        volume_naming: "volume",
      )

      expect(options.max_volume_size).to eq(10_485_760)
      expect(options.volume_naming).to eq("volume")
    end
  end

  describe "#validate!" do
    it "accepts valid volume size" do
      options = described_class.new(max_volume_size: 1_048_576) # 1 MB

      expect { options.validate! }.not_to raise_error
    end

    it "accepts minimum volume size (64 KB)" do
      options = described_class.new(max_volume_size: 65_536)

      expect { options.validate! }.not_to raise_error
    end

    it "rejects volume size below minimum" do
      options = described_class.new(max_volume_size: 32_768) # 32 KB

      expect do
        options.validate!
      end.to raise_error(ArgumentError, /at least 64 KB/)
    end

    it "rejects zero volume size" do
      options = described_class.new(max_volume_size: 0)

      expect { options.validate! }.to raise_error(ArgumentError)
    end
  end

  describe ".parse_size" do
    it "parses integer bytes" do
      result = described_class.parse_size(1024)

      expect(result).to eq(1024)
    end

    it "parses kilobytes" do
      result = described_class.parse_size("10K")

      expect(result).to eq(10_240)
    end

    it "parses megabytes" do
      result = described_class.parse_size("10M")

      expect(result).to eq(10_485_760)
    end

    it "parses gigabytes" do
      result = described_class.parse_size("1G")

      expect(result).to eq(1_073_741_824)
    end

    it "parses terabytes" do
      result = described_class.parse_size("1T")

      expect(result).to eq(1_099_511_627_776)
    end

    it "parses bytes without suffix" do
      result = described_class.parse_size("1024")

      expect(result).to eq(1024)
    end

    it "parses decimal values" do
      result = described_class.parse_size("1.5M")

      expect(result).to eq(1_572_864)
    end

    it "handles lowercase suffixes" do
      result = described_class.parse_size("10m")

      expect(result).to eq(10_485_760)
    end

    it "handles whitespace" do
      result = described_class.parse_size("10 M")

      expect(result).to eq(10_485_760)
    end

    it "raises error for invalid format" do
      expect do
        described_class.parse_size("invalid")
      end.to raise_error(ArgumentError,
                         /Invalid size format/)
    end
  end
end
