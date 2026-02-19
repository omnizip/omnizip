# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Filters::BCJ do
  describe "#initialize" do
    it "accepts supported architectures" do
      %i[x86 arm arm64 powerpc ia64 sparc].each do |arch|
        expect { described_class.new(architecture: arch) }.not_to raise_error
      end
    end

    it "rejects unsupported architecture" do
      expect { described_class.new(architecture: :riscv) }
        .to raise_error(ArgumentError, /Unsupported/)
    end

    it "stores architecture" do
      bcj = described_class.new(architecture: :x86)
      expect(bcj.architecture).to eq(:x86)
    end

    it "sets name based on architecture" do
      bcj = described_class.new(architecture: :x86)
      expect(bcj.name).to eq("BCJ-X86")
    end
  end

  describe "#id_for_format" do
    context "x86 architecture" do
      let(:bcj) { described_class.new(architecture: :x86) }

      it "returns XZ format ID" do
        expect(bcj.id_for_format(:xz)).to eq(0x04)
      end

      it "returns 7z format ID" do
        expect(bcj.id_for_format(:seven_zip)).to eq(0x03030103)
      end

      it "raises for unknown format" do
        expect { bcj.id_for_format(:zip) }
          .to raise_error(ArgumentError, /Unknown format/)
      end
    end

    context "arm64 architecture" do
      let(:bcj) { described_class.new(architecture: :arm64) }

      it "returns 7z format ID" do
        expect(bcj.id_for_format(:seven_zip)).to eq(0x03030601)
      end

      it "raises for XZ format (not yet supported)" do
        expect { bcj.id_for_format(:xz) }
          .to raise_error(NotImplementedError, /not yet supported/)
      end
    end

    # Test all architectures have 7z IDs
    %i[x86 arm arm64 powerpc ia64 sparc].each do |arch|
      context "#{arch} architecture" do
        let(:bcj) { described_class.new(architecture: arch) }

        it "has 7z format ID" do
          expect(bcj.id_for_format(:seven_zip)).to be_a(Integer)
          expect(bcj.id_for_format(:seven_zip)).to be > 0
        end
      end
    end
  end

  describe "#encode and #decode" do
    let(:bcj) { described_class.new(architecture: :x86) }

    it "roundtrips data correctly" do
      # CALL instruction with relative offset 0 (use binary encoding)
      original = "\xE8\x00\x00\x00\x00\x00".b
      encoded = bcj.encode(original, 0)
      decoded = bcj.decode(encoded, 0)
      expect(decoded).to eq(original)
    end

    it "handles empty data" do
      expect(bcj.encode("")).to eq("")
      expect(bcj.decode("")).to eq("")
    end

    it "handles data smaller than instruction size" do
      short_data = "ABC".b
      expect(bcj.encode(short_data)).to eq(short_data)
      expect(bcj.decode(short_data)).to eq(short_data)
    end

    it "preserves data without branch instructions" do
      no_branch_data = "Hello World! This is test data.".b
      expect(bcj.encode(no_branch_data)).to eq(no_branch_data)
      expect(bcj.decode(no_branch_data)).to eq(no_branch_data)
    end

    it "handles JMP instruction (0xE9)" do
      original = "\xE9\x00\x00\x00\x00".b
      encoded = bcj.encode(original, 0)
      decoded = bcj.decode(encoded, 0)
      expect(decoded).to eq(original)
    end

    it "respects position parameter" do
      original = "\xE8\x00\x00\x00\x00".b
      encoded_at_position_hundred = bcj.encode(original, 100)
      decoded_at_position_hundred = bcj.decode(encoded_at_position_hundred, 100)
      expect(decoded_at_position_hundred).to eq(original)
    end
  end

  describe "#encode" do
    let(:bcj) { described_class.new(architecture: :x86) }

    it "converts relative to absolute addresses" do
      # CALL with relative offset of 0
      # At position 0, instruction at index 0
      # Target = 0 (offset) + 0 (position) + 0 (index) + 5 (instruction size) = 5
      original = "\xE8\x00\x00\x00\x00".b
      encoded = bcj.encode(original, 0)

      # The address should now be 5 (0x05 0x00 0x00 0x00 in little-endian)
      expect(encoded.getbyte(1)).to eq(0x05)
      expect(encoded.getbyte(2)).to eq(0x00)
      expect(encoded.getbyte(3)).to eq(0x00)
      expect(encoded.getbyte(4)).to eq(0x00)
    end

    it "only processes valid relative addresses" do
      # Data with 0xE8 byte but not a valid address (high byte not 0x00 or 0xFF)
      # High byte 0x80 makes it invalid
      original = "\xE8\x00\x00\x00\x80".b
      # Should not modify since invalid
      expect(bcj.encode(original)).to eq(original)
    end

    it "skips non-branch opcodes" do
      original = "\x01\x02\x03\x04\x05".b * 2
      expect(bcj.encode(original)).to eq(original)
    end
  end

  describe "#decode" do
    let(:bcj) { described_class.new(architecture: :x86) }

    it "converts absolute to relative addresses" do
      # Start with an absolute address of 5
      absolute_data = "\xE8\x05\x00\x00\x00".b
      decoded = bcj.decode(absolute_data, 0)

      # Should convert back to relative offset of 0
      expect(decoded.getbyte(1)).to eq(0x00)
      expect(decoded.getbyte(2)).to eq(0x00)
      expect(decoded.getbyte(3)).to eq(0x00)
      expect(decoded.getbyte(4)).to eq(0x00)
    end
  end

  describe "#encode with different architectures" do
    it "works for ARM architecture" do
      bcj_arm = described_class.new(architecture: :arm)
      # ARM has instruction_size: 4, need data >= instruction_size
      # Use longer data to avoid index errors during encoding
      test_data = "\x0A\x00\x00\x00\x00\x00\x00\x00".b
      result = bcj_arm.encode(test_data)
      expect(result).to be_a(String)
      expect(result.bytesize).to eq(test_data.bytesize)
    end

    it "works for PowerPC architecture" do
      bcj_ppc = described_class.new(architecture: :powerpc)
      # PowerPC has instruction_size: 4, need data >= instruction_size
      test_data = "\x48\x00\x00\x00\x00\x00\x00\x00".b
      result = bcj_ppc.encode(test_data)
      expect(result).to be_a(String)
      expect(result.bytesize).to eq(test_data.bytesize)
    end

    it "works for IA64 architecture" do
      bcj_ia64 = described_class.new(architecture: :ia64)
      # IA64 has instruction_size: 4, need data >= instruction_size
      test_data = "\x04\x00\x00\x00\x00\x00\x00\x00".b
      result = bcj_ia64.encode(test_data)
      expect(result).to be_a(String)
      expect(result.bytesize).to eq(test_data.bytesize)
    end

    it "works for SPARC architecture" do
      bcj_sparc = described_class.new(architecture: :sparc)
      # SPARC has instruction_size: 4, need data >= instruction_size
      test_data = "\x04\x00\x00\x00\x00\x00\x00\x00".b
      result = bcj_sparc.encode(test_data)
      expect(result).to be_a(String)
      expect(result.bytesize).to eq(test_data.bytesize)
    end
  end

  describe ".metadata" do
    it "returns filter metadata" do
      metadata = described_class.metadata
      expect(metadata[:name]).to eq("BCJ")
      expect(metadata[:description])
        .to eq("Branch/Call/Jump converter for executable files")
      expect(metadata[:supported_architectures]).to include(:x86, :arm, :arm64)
    end

    it "includes architecture descriptions" do
      metadata = described_class.metadata
      expect(metadata[:architectures]).to be_a(Hash)
      expect(metadata[:architectures][:x86]).to eq("x86/x86-64")
      expect(metadata[:architectures][:arm]).to eq("ARM 32-bit")
      expect(metadata[:architectures][:arm64]).to eq("ARM 64-bit")
    end
  end
end
