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
end
