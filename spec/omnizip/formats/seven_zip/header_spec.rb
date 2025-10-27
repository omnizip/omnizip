# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::SevenZip::Header do
  describe ".read" do
    it "parses valid .7z file header" do
      fixture = File.join(__dir__, "../../../fixtures/seven_zip",
                          "simple_copy.7z")
      File.open(fixture, "rb") do |io|
        header = described_class.read(io)

        expect(header).to be_valid
        expect(header.major_version).to eq(0)
        expect(header.next_header_offset).to be_a(Integer)
        expect(header.next_header_size).to be > 0
      end
    end

    it "validates signature correctly" do
      fixture = File.join(__dir__, "../../../fixtures/seven_zip",
                          "simple_lzma.7z")
      File.open(fixture, "rb") do |io|
        header = described_class.read(io)
        expect(header).to be_valid
      end
    end

    it "rejects invalid signature" do
      # Create temp file with bad signature
      require "tempfile"
      Tempfile.create(["bad", ".7z"]) do |f|
        f.write("BAD_SIG\x00" * 10)
        f.rewind

        expect do
          described_class.read(f)
        end.to raise_error(RuntimeError, /Invalid .7z signature/)
      end
    end

    it "validates start header CRC" do
      fixture = File.join(__dir__, "../../../fixtures/seven_zip",
                          "multi_file.7z")
      File.open(fixture, "rb") do |io|
        # Should not raise CRC error with valid file
        expect { described_class.read(io) }.not_to raise_error
      end
    end
  end
end
