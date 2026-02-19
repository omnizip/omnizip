# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require "spec_helper"
require "tempfile"
require "fileutils"
require "open3"

RSpec.describe "XZ Bidirectional Compatibility" do
  # Check if xz utility is available
  let(:xz_available) do
    @xz_checked ||= system("which xz > /dev/null 2>&1")
  end

  # Test data patterns
  let(:test_patterns) do
    {
      empty: "",
      single_char: "a",
      short_text: "Hello, World!",
      long_text: "The quick brown fox jumps over the lazy dog. " * 10,
      numeric: "0123456789" * 50,
      mixed: "ABCdef123!@#" * 20,
      repetitive: "aaaa" * 100, # Highly compressible
      alternating: "AB" * 500, # Alternating pattern
      newlines: "Line 1\nLine 2\nLine 3\n" * 20,
      binary: (0..255).to_a.pack("C*") * 10, # All byte values
      random: Random.new(42).bytes(1000), # Reproducible random data
    }
  end

  # Test data sizes
  let(:test_sizes) do
    [0, 1, 10, 50, 100, 500, 1000, 5000, 10000]
  end

  # Helper method to check xz availability
  def skip_unless_xz_available
    skip "xz utility not available - install with: brew install xz (macOS) or apt install xzutils (Linux)" unless xz_available
  end

  # Helper: compress with Omnizip XZ encoder
  def compress_with_omnizip(data, options = {})
    Omnizip::Formats::Xz.create(data, nil, options)
  end

  # Helper: decompress with Omnizip XZ decoder
  def decompress_with_omnizip(xz_data)
    # Use StringIO for in-memory data (avoid file path detection issues)
    io = StringIO.new(xz_data)
    io.set_encoding("ASCII-8BIT")
    Omnizip::Formats::Xz.decompress(io)
  end

  # Helper: compress with system xz
  def compress_with_xz(data, level = 6)
    stdout, stderr, status = Open3.capture3("xz -#{level} -c", stdin_data: data)
    raise "xz compression failed: #{stderr}" unless status.success?

    stdout
  end

  # Helper: decompress with system xz
  def decompress_with_xz(xz_data)
    stdout, stderr, status = Open3.capture3("xz -d -c", stdin_data: xz_data)
    raise "xz decompression failed: #{stderr}" unless status.success?

    # Open3 returns stdout with UTF-8 encoding, but binary data needs ASCII-8BIT
    # Force encoding to ensure proper comparison with binary test data
    stdout.force_encoding(Encoding::BINARY)
  end

  # Helper: verify xz file validity with xz -t
  def verify_with_xz(xz_data)
    Tempfile.create("test.xz") do |f|
      f.binmode
      f.write(xz_data)
      f.close

      _, stderr, status = Open3.capture3("xz -t #{f.path}")
      [status.success?, stderr]
    end
  end

  # Helper: get xz file info with xz -l
  def info_with_xz(xz_data)
    Tempfile.create("test.xz") do |f|
      f.binmode
      f.write(xz_data)
      f.close

      stdout, stderr, status = Open3.capture3("xz -l #{f.path}")
      [status.success?, stdout, stderr]
    end
  end

  describe "Omnizip encoder → XZ decoder" do
    context "with various data patterns" do
      it "compresses and decompresses all test patterns correctly" do
        skip_unless_xz_available

        test_patterns.each do |pattern_name, data|
          # Compress with Omnizip
          compressed = compress_with_omnizip(data)

          # Verify with xz -t
          is_valid, stderr = verify_with_xz(compressed)
          expect(is_valid).to be(true),
                              "xz -t validation failed for #{pattern_name}: #{stderr}"

          # Decompress with xz
          decompressed = decompress_with_xz(compressed)

          # Verify data integrity
          expect(decompressed).to eq(data),
                                  "Data mismatch after Omnizip → XZ round-trip for #{pattern_name}"
        end
      end
    end

    context "with various data sizes" do
      it "handles all test sizes correctly" do
        skip_unless_xz_available

        test_sizes.each do |size|
          data = "x" * size
          compressed = compress_with_omnizip(data)

          # Verify validity
          is_valid, stderr = verify_with_xz(compressed)
          expect(is_valid).to be(true),
                              "xz -t validation failed for #{size} bytes: #{stderr}"

          # Decompress and verify
          decompressed = decompress_with_xz(compressed)
          expect(decompressed).to eq(data)
        end
      end
    end

    context "XZ file inspection" do
      it "produces files inspectable with xz -l" do
        skip_unless_xz_available

        data = test_patterns[:long_text]
        compressed = compress_with_omnizip(data)

        is_valid, stdout, stderr = info_with_xz(compressed)
        expect(is_valid).to be(true), "xz -l failed: #{stderr}"
        expect(stdout).to include("Strms") # Stream count
        expect(stdout).to include("Blocks") # Block count
      end
    end

    context "compression levels (dict_size options)" do
      # Note: Our encoder uses dict_size, not compression levels directly
      it "works with various dictionary sizes" do
        skip_unless_xz_available

        dict_sizes = [
          { dict_size: 4096, name: "4KB" },
          { dict_size: 8 * 1024, name: "8KB" },
          { dict_size: 1024 * 1024, name: "1MB" },
          { dict_size: 8 * 1024 * 1024, name: "8MB" },
        ]

        dict_sizes.each do |config|
          data = test_patterns[:long_text]
          compressed = compress_with_omnizip(data,
                                             dict_size: config[:dict_size])

          is_valid, stderr = verify_with_xz(compressed)
          expect(is_valid).to be(true),
                              "xz -t failed with #{config[:name]} dict: #{stderr}"

          decompressed = decompress_with_xz(compressed)
          expect(decompressed).to eq(data),
                                  "Failed with #{config[:name]} dictionary"
        end
      end
    end
  end

  describe "XZ encoder → Omnizip decoder" do
    context "with various data patterns" do
      it "decompresses all test patterns correctly" do
        skip_unless_xz_available

        test_patterns.each do |pattern_name, data|
          # Compress with xz (default level 6)
          compressed = compress_with_xz(data, 6)

          # Decompress with Omnizip
          decompressed = decompress_with_omnizip(compressed)

          # Verify data integrity
          expect(decompressed).to eq(data),
                                  "Data mismatch after XZ → Omnizip round-trip for #{pattern_name}"
        end
      end
    end

    context "with various compression levels" do
      it "handles all compression levels" do
        skip_unless_xz_available

        [0, 1, 3, 6, 9].each do |level|
          data = test_patterns[:long_text]
          compressed = compress_with_xz(data, level)
          decompressed = decompress_with_omnizip(compressed)
          expect(decompressed).to eq(data),
                                  "Failed at compression level #{level}"
        end
      end
    end

    context "with various data sizes" do
      it "handles all test sizes correctly" do
        skip_unless_xz_available

        test_sizes.each do |size|
          data = "x" * size
          compressed = compress_with_xz(data, 6)
          decompressed = decompress_with_omnizip(compressed)
          expect(decompressed).to eq(data), "Failed with #{size} bytes"
        end
      end
    end

    context "extreme compression" do
      it "handles highly repetitive data (xz -9)" do
        skip_unless_xz_available

        data = "A" * 10000
        compressed = compress_with_xz(data, 9)
        decompressed = decompress_with_omnizip(compressed)
        expect(decompressed).to eq(data)
      end

      it "handles no compression (xz -0)" do
        skip_unless_xz_available

        data = test_patterns[:random]
        compressed = compress_with_xz(data, 0)
        decompressed = decompress_with_omnizip(compressed)
        expect(decompressed).to eq(data)
      end
    end
  end

  describe "Bidirectional round-trip tests" do
    context "Omnizip → XZ → Omnizip" do
      it "round-trips all test patterns correctly" do
        skip_unless_xz_available

        test_patterns.each do |pattern_name, data|
          # Omnizip encode
          compressed1 = compress_with_omnizip(data)

          # XZ decode
          decompressed = decompress_with_xz(compressed1)

          # Omnizip encode again
          compressed2 = compress_with_omnizip(decompressed)

          # Verify
          expect(decompressed).to eq(data),
                                  "Round-trip failed for #{pattern_name}"
          expect(compressed2.bytesize).to be_within(100).of(compressed1.bytesize),
                                          "Compression size changed for #{pattern_name}"
        end
      end
    end

    context "XZ → Omnizip → XZ" do
      it "round-trips all test patterns correctly" do
        skip_unless_xz_available

        test_patterns.each do |pattern_name, data|
          # XZ encode
          compressed1 = compress_with_xz(data, 6)

          # Omnizip decode
          decompressed = decompress_with_omnizip(compressed1)

          # XZ encode again
          compress_with_xz(decompressed, 6)

          # Verify
          expect(decompressed).to eq(data),
                                  "Round-trip failed for #{pattern_name}"
        end
      end
    end

    context "Full round-trip: Omnizip → XZ → Omnizip → XZ" do
      it "maintains data integrity through full cycle" do
        skip_unless_xz_available

        original = test_patterns[:binary]

        # Omnizip → XZ → Omnizip → XZ
        step1 = compress_with_omnizip(original)
        step2 = decompress_with_xz(step1)
        step3 = compress_with_omnizip(step2)
        step4 = decompress_with_xz(step3)

        expect(step2).to eq(original)
        expect(step4).to eq(original)
      end
    end
  end

  describe "Edge cases and error handling" do
    context "omnizip to xz" do
      it "handles empty file correctly" do
        skip_unless_xz_available

        data = ""
        compressed = compress_with_omnizip(data)
        decompressed = decompress_with_xz(compressed)
        expect(decompressed).to eq(data)
      end

      it "handles single byte correctly" do
        skip_unless_xz_available

        data = "\x00"
        compressed = compress_with_omnizip(data)
        decompressed = decompress_with_xz(compressed)
        expect(decompressed).to eq(data)
      end

      it "handles very large file (1MB)" do
        skip_unless_xz_available

        data = "x" * (1024 * 1024)
        compressed = compress_with_omnizip(data)
        decompressed = decompress_with_xz(compressed)
        expect(decompressed).to eq(data)
      end
    end

    context "xz to omnizip" do
      it "handles empty file correctly" do
        skip_unless_xz_available

        data = ""
        compressed = compress_with_xz(data, 6)
        decompressed = decompress_with_omnizip(compressed)
        expect(decompressed).to eq(data)
      end

      it "handles single byte correctly" do
        skip_unless_xz_available

        data = "\x00"
        compressed = compress_with_xz(data, 6)
        decompressed = decompress_with_omnizip(compressed)
        expect(decompressed).to eq(data)
      end

      it "handles very large file (1MB)" do
        skip_unless_xz_available

        data = "x" * (1024 * 1024)
        compressed = compress_with_xz(data, 6)
        decompressed = decompress_with_omnizip(compressed)
        expect(decompressed).to eq(data)
      end
    end
  end

  describe "Compatibility test documentation" do
    it "records test environment information" do
      skip_unless_xz_available

      # Get xz version
      stdout, _stderr, status = Open3.capture3("xz --version")
      xz_version = status.success? ? stdout.lines.first : "unknown"

      # Document in test output
      puts "\n=== XZ Compatibility Test Environment ==="
      puts "XZ Version: #{xz_version.strip}"
      puts "Ruby Version: #{RUBY_VERSION}"
      puts "Test Patterns: #{test_patterns.keys.join(', ')}"
      puts "Test Sizes: #{test_sizes.join(', ')}"
      puts "==========================================\n"
    end
  end
end
