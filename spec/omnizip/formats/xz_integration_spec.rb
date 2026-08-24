# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/xz"
require "tempfile"

RSpec.describe "XZ Format Integration" do
  describe "cross-compatibility with xz command" do
    let(:test_data) do
      "Hello, XZ format! This is a test of LZMA2 compression." * 100
    end

    it "creates .xz file that xz can decompress" do
      Tempfile.create(["omnizip_test", ".xz"]) do |xz_file|
        # Create .xz file with Omnizip
        Omnizip::Formats::Xz.create(test_data, xz_file.path)

        # Try to decompress with system xz command
        Tempfile.create(["decoded", ".txt"]) do |output_file|
          # Use xz -dc to decompress
          result = system("xz", "-dc", xz_file.path, out: output_file.path,
                                                     err: File::NULL)

          # Check if xz command succeeded
          expect(result).to be_truthy, "xz command failed to decompress file"

          # Verify decompressed content matches original
          decompressed = File.binread(output_file.path)
          expect(decompressed).to eq(test_data)
        end
      end
    end

    it "creates valid XZ stream structure" do
      compressed = Omnizip::Formats::Xz.create(test_data)

      # Verify magic bytes
      magic = compressed[0, 6].bytes
      expect(magic).to eq([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])

      # Verify footer magic
      footer_magic = compressed[-2, 2].bytes
      expect(footer_magic).to eq([0x59, 0x5A])

      # Verify stream header size
      expect(compressed.bytesize).to be > 12 # At least header size
    end

    it "handles small data correctly" do
      small_data = "Hi"

      Tempfile.create(["small_test", ".xz"]) do |xz_file|
        Omnizip::Formats::Xz.create(small_data, xz_file.path)

        Tempfile.create(["decoded_small", ".txt"]) do |output_file|
          result = system("xz", "-dc", xz_file.path, out: output_file.path,
                                                     err: File::NULL)

          expect(result).to be_truthy
          decompressed = File.binread(output_file.path)
          expect(decompressed).to eq(small_data)
        end
      end
    end

    it "handles binary data correctly" do
      binary_data = (0..255).to_a.pack("C*") * 50

      Tempfile.create(["binary_test", ".xz"]) do |xz_file|
        Omnizip::Formats::Xz.create(binary_data, xz_file.path)

        Tempfile.create(["decoded_binary", ".bin"]) do |output_file|
          result = system("xz", "-dc", xz_file.path, out: output_file.path,
                                                     err: File::NULL)

          expect(result).to be_truthy
          decompressed = File.binread(output_file.path)
          expect(decompressed).to eq(binary_data)
        end
      end
    end
  end

  describe "Builder API" do
    it "supports block syntax for file creation" do
      Tempfile.create(["builder_test", ".xz"]) do |xz_file|
        Omnizip::Formats::Xz.create_file(xz_file.path) do |builder|
          builder.add_data("Part 1: ")
          builder.add_data("Part 2: ")
          builder.add_data("Part 3")
        end

        Tempfile.create(["decoded_builder", ".txt"]) do |output_file|
          result = system("xz", "-dc", xz_file.path, out: output_file.path,
                                                     err: File::NULL)

          expect(result).to be_truthy
          decompressed = File.binread(output_file.path)
          expect(decompressed).to eq("Part 1: Part 2: Part 3")
        end
      end
    end
  end

  describe "multi-chunk streams (issue #26)" do
    # LZMA2 stores at most 2 MiB uncompressed and 64 KiB compressed per
    # chunk; inputs beyond those limits exercise chunk continuation.
    let(:word_text) do
      rng = Random.new(7)
      words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit sed
                 do eiusmod tempor incididunt ut labore]
      Array.new(60_000) { words[rng.rand(words.size)] }.join(" ")
    end

    it "round-trips data spanning the 2 MiB uncompressed chunk limit" do
      data = "a" * 2_100_000
      compressed = Omnizip::Formats::Xz.create(data)
      expect(Omnizip::Formats::Xz.decode(compressed)).to eq(data)
    end

    it "round-trips data whose compressed chunk exceeds the 64 KiB cap" do
      compressed = Omnizip::Formats::Xz.create(word_text)
      expect(compressed.bytesize).to be > 65_536
      expect(Omnizip::Formats::Xz.decode(compressed)).to eq(word_text)
    end

    it "does not overflow the range encoder symbol buffer on far matches" do
      # Two literals leave the queue at 18 symbols; a 2 MiB-distance match
      # with a high distance slot queues ~37 more, exceeding the
      # XzRangeEncoder's 53-symbol buffer unless it is drained per item.
      rng = Random.new(42)
      unit = Array.new(3000) { (65 + rng.rand(26)).chr }.join
      data = "#{'a' * 600_000}#{unit}#{'a' * 2_000_022}QZ#{unit}"

      compressed = Omnizip::Formats::Xz.create(data)
      expect(Omnizip::Formats::Xz.decode(compressed)).to eq(data)
    end

    it "emits streams the system xz accepts for multi-chunk data" do
      Tempfile.create(["omnizip_multichunk", ".xz"]) do |xz_file|
        Omnizip::Formats::Xz.create(word_text, xz_file.path)

        Tempfile.create(["decoded_multichunk", ".txt"]) do |output_file|
          result = system("xz", "-dc", xz_file.path, out: output_file.path,
                                                     err: File::NULL)
          expect(result).to be_truthy
          expect(File.binread(output_file.path)).to eq(word_text)
        end
      end
    end
  end
end
