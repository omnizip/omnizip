# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Rar5::Header do
  describe Omnizip::Formats::Rar::Rar5::MainHeader do
    it "creates main header" do
      header = described_class.new
      encoded = header.encode

      expect(encoded).not_to be_empty
      expect(encoded[0..3]).to be_a(String) # CRC32
    end
  end

  describe Omnizip::Formats::Rar::Rar5::FileHeader do
    it "creates file header" do
      header = described_class.new(
        filename: "test.txt",
        file_size: 100,
        compressed_size: 100,
      )
      encoded = header.encode

      expect(encoded).not_to be_empty
      expect(encoded).to include("test.txt")
    end
  end

  describe Omnizip::Formats::Rar::Rar5::EndHeader do
    it "creates end header" do
      header = described_class.new
      encoded = header.encode

      expect(encoded).not_to be_empty
      expect(encoded.bytesize).to be < 50 # Should be minimal
    end
  end
end
