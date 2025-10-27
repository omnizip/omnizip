# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::ChecksumRegistry do
  # Clear registry before each test to ensure isolation
  before do
    described_class.clear
  end

  after do
    # Re-register the checksums after tests only if not already registered
    unless described_class.registered?(:crc32)
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
    end
    unless described_class.registered?(:crc64)
      described_class.register(:crc64, Omnizip::Checksums::Crc64)
    end
  end

  describe ".register" do
    it "registers a new checksum algorithm" do
      described_class.register(:test_crc, Omnizip::Checksums::Crc32)

      expect(described_class.available).to include(:test_crc)
    end

    it "raises error when registering duplicate name" do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)

      expect do
        described_class.register(:crc32, Omnizip::Checksums::Crc64)
      end.to raise_error(
        ArgumentError,
        "Checksum 'crc32' is already registered"
      )
    end

    it "accepts symbol names" do
      described_class.register(:my_checksum, Omnizip::Checksums::Crc32)

      expect(described_class.registered?(:my_checksum)).to be true
    end

    it "converts string names to symbols" do
      described_class.register("my_checksum", Omnizip::Checksums::Crc32)

      expect(described_class.registered?(:my_checksum)).to be true
    end
  end

  describe ".get" do
    before do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
      described_class.register(:crc64, Omnizip::Checksums::Crc64)
    end

    it "retrieves a registered checksum class" do
      checksum_class = described_class.get(:crc32)

      expect(checksum_class).to eq(Omnizip::Checksums::Crc32)
    end

    it "accepts symbol names" do
      checksum_class = described_class.get(:crc32)

      expect(checksum_class).to eq(Omnizip::Checksums::Crc32)
    end

    it "accepts string names" do
      checksum_class = described_class.get("crc32")

      expect(checksum_class).to eq(Omnizip::Checksums::Crc32)
    end

    it "raises error for unknown checksum" do
      expect do
        described_class.get(:unknown)
      end.to raise_error(
        Omnizip::UnknownAlgorithmError,
        /Unknown checksum: 'unknown'/
      )
    end

    it "includes available checksums in error message" do
      expect do
        described_class.get(:nonexistent)
      end.to raise_error(
        Omnizip::UnknownAlgorithmError,
        /Available: crc32, crc64/
      )
    end
  end

  describe ".available" do
    it "returns empty array when no checksums registered" do
      expect(described_class.available).to eq([])
    end

    it "returns array of registered checksum names" do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
      described_class.register(:crc64, Omnizip::Checksums::Crc64)

      expect(described_class.available).to contain_exactly(:crc32, :crc64)
    end

    it "returns sorted array" do
      described_class.register(:zebra, Omnizip::Checksums::Crc32)
      described_class.register(:alpha, Omnizip::Checksums::Crc64)
      described_class.register(:beta, Omnizip::Checksums::Crc32)

      expect(described_class.available).to eq(%i[alpha beta zebra])
    end
  end

  describe ".registered?" do
    before do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
    end

    it "returns true for registered checksums" do
      expect(described_class.registered?(:crc32)).to be true
    end

    it "returns false for unregistered checksums" do
      expect(described_class.registered?(:unknown)).to be false
    end

    it "accepts string names" do
      expect(described_class.registered?("crc32")).to be true
    end
  end

  describe ".clear" do
    it "removes all registered checksums" do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
      described_class.register(:crc64, Omnizip::Checksums::Crc64)

      described_class.clear

      expect(described_class.available).to be_empty
    end

    it "allows re-registration after clear" do
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
      described_class.clear
      described_class.register(:crc32, Omnizip::Checksums::Crc64)

      expect(described_class.get(:crc32)).to eq(Omnizip::Checksums::Crc64)
    end
  end

  describe "default registrations" do
    before do
      # Use the actual registration from lib/omnizip.rb
      described_class.register(:crc32, Omnizip::Checksums::Crc32)
      described_class.register(:crc64, Omnizip::Checksums::Crc64)
    end

    it "has CRC32 registered" do
      expect(described_class.registered?(:crc32)).to be true
      expect(described_class.get(:crc32)).to eq(Omnizip::Checksums::Crc32)
    end

    it "has CRC64 registered" do
      expect(described_class.registered?(:crc64)).to be true
      expect(described_class.get(:crc64)).to eq(Omnizip::Checksums::Crc64)
    end

    it "can instantiate registered checksums" do
      crc32_class = described_class.get(:crc32)
      crc32 = crc32_class.new

      expect(crc32).to be_a(Omnizip::Checksums::Crc32)
    end

    it "can calculate checksums using registered classes" do
      crc32_class = described_class.get(:crc32)
      result = crc32_class.calculate("test")

      expect(result).to be_a(Integer)
    end
  end
end
