# frozen_string_literal: true

require "spec_helper"
require "omnizip/filters/bcj_arm"
require "omnizip/filters/bcj_arm64"
require "omnizip/filters/bcj_ppc"
require "omnizip/filters/bcj_sparc"
require "omnizip/filters/bcj_ia64"

RSpec.describe "Architecture-specific BCJ filters" do
  describe Omnizip::Filters::BcjArm do
    let(:filter) { described_class.new }

    describe ".metadata" do
      it "returns correct filter metadata" do
        metadata = described_class.metadata
        expect(metadata[:name]).to eq("BCJ-ARM")
        expect(metadata[:architecture]).to eq("ARM (32-bit)")
        expect(metadata[:alignment]).to eq(4)
        expect(metadata[:endian]).to eq("little")
      end
    end

    describe "#encode and #decode" do
      it "correctly encodes and decodes ARM BL instructions" do
        # Create mock ARM BL instruction (0xEB000000 + offset)
        # BL instruction with 24-bit offset
        data = [0x00, 0x00, 0x00, 0xEB].pack("C*")

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "preserves non-BL instructions" do
        # Random non-BL instruction
        data = [0x12, 0x34, 0x56, 0x78].pack("C*")

        encoded = filter.encode(data, 0)

        expect(encoded).to eq(data)
      end

      it "handles empty data" do
        data = ""

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end
  end

  describe Omnizip::Filters::BcjArm64 do
    let(:filter) { described_class.new }

    describe ".metadata" do
      it "returns correct filter metadata" do
        metadata = described_class.metadata
        expect(metadata[:name]).to eq("BCJ-ARM64")
        expect(metadata[:architecture]).to eq("ARM64 / AArch64")
        expect(metadata[:alignment]).to eq(4)
        expect(metadata[:endian]).to eq("little")
      end
    end

    describe "#encode and #decode" do
      it "correctly encodes and decodes ARM64 B/BL instructions" do
        # Create mock ARM64 B instruction (0x14000000)
        data = [0x00, 0x00, 0x00, 0x94].pack("C*")

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "preserves non-branch instructions" do
        data = [0x12, 0x34, 0x56, 0x78].pack("C*")

        encoded = filter.encode(data, 0)

        expect(encoded).to eq(data)
      end

      it "handles short data" do
        data = "AB"

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end
  end

  describe Omnizip::Filters::BcjPpc do
    let(:filter) { described_class.new }

    describe ".metadata" do
      it "returns correct filter metadata" do
        metadata = described_class.metadata
        expect(metadata[:name]).to eq("BCJ-PPC")
        expect(metadata[:architecture]).to eq("PowerPC")
        expect(metadata[:alignment]).to eq(4)
        expect(metadata[:endian]).to eq("big")
      end
    end

    describe "#encode and #decode" do
      it "correctly encodes and decodes PPC B/BL instructions" do
        # Create mock PPC BL instruction (0x48000001 big-endian)
        data = [0x48, 0x00, 0x00, 0x01].pack("C*")

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "preserves non-branch instructions" do
        data = [0x12, 0x34, 0x56, 0x78].pack("C*")

        encoded = filter.encode(data, 0)

        expect(encoded).to eq(data)
      end

      it "handles data not matching instruction pattern" do
        data = [0x00, 0x00, 0x00, 0x00].pack("C*")

        encoded = filter.encode(data, 0)

        expect(encoded).to eq(data)
      end
    end
  end

  describe Omnizip::Filters::BcjSparc do
    let(:filter) { described_class.new }

    describe ".metadata" do
      it "returns correct filter metadata" do
        metadata = described_class.metadata
        expect(metadata[:name]).to eq("BCJ-SPARC")
        expect(metadata[:architecture]).to eq("SPARC")
        expect(metadata[:alignment]).to eq(4)
        expect(metadata[:endian]).to eq("big")
      end
    end

    describe "#encode and #decode" do
      it "is reversible for any aligned data" do
        # Use data that might trigger SPARC instruction detection
        data = [0x40, 0x00, 0x00, 0x00].pack("C*")

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "handles non-instruction data" do
        data = [0x00, 0x00, 0x00, 0x00].pack("C*")

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end
  end

  describe Omnizip::Filters::BcjIa64 do
    let(:filter) { described_class.new }

    describe ".metadata" do
      it "returns correct filter metadata" do
        metadata = described_class.metadata
        expect(metadata[:name]).to eq("BCJ-IA64")
        expect(metadata[:architecture]).to eq("IA-64 / Itanium")
        expect(metadata[:alignment]).to eq(16)
        expect(metadata[:endian]).to eq("little")
        expect(metadata[:complexity]).to eq("high")
      end
    end

    describe "#encode and #decode" do
      it "correctly handles 16-byte bundles" do
        # Create a 16-byte IA-64 instruction bundle
        # Template byte + 3x 41-bit instructions
        data = "\x00" * 16

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "handles data shorter than bundle size" do
        data = "SHORT"

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "processes only complete 16-byte bundles" do
        # 32 bytes = 2 complete bundles
        data = "\x00" * 32

        encoded = filter.encode(data, 0)
        decoded = filter.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end
  end

  # Cross-filter integration tests
  describe "Filter reversibility" do
    let(:filters) do
      [
        Omnizip::Filters::BcjArm.new,
        Omnizip::Filters::BcjArm64.new,
        Omnizip::Filters::BcjPpc.new,
        Omnizip::Filters::BcjSparc.new,
        Omnizip::Filters::BcjIa64.new
      ]
    end

    it "all filters maintain encode/decode reversibility" do
      # Test with various data patterns
      # Note: BCJ filters are designed for executable code, so we use
      # patterns that won't accidentally match instruction opcodes
      test_data = [
        "\x00" * 64,                          # Zeros
        "\x01" * 64,                          # All ones (not 0xEB/0x94/etc)
        (0..63).map { |i| (i % 128).chr }.join, # Sequential (safe range)
        "\x12\x34\x56\x78" * 16                 # Safe pattern
      ]

      filters.each do |filter|
        test_data.each do |data|
          encoded = filter.encode(data, 0)
          decoded = filter.decode(encoded, 0)
          expect(decoded).to eq(data),
                             "#{filter.class} failed reversibility"
        end
      end
    end

    it "all filters handle position offset correctly" do
      data = "\x00" * 32

      filters.each do |filter|
        [0, 100, 1000, 10_000].each do |position|
          encoded = filter.encode(data, position)
          decoded = filter.decode(encoded, position)
          expect(decoded).to eq(data),
                             "#{filter.class} failed at position #{position}"
        end
      end
    end
  end
end
