# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "XZ Official Test Suite" do
  FIXTURES_DIR = File.join(__dir__, "../../../fixtures/xz/official")

  before(:all) do
    skip "XZ test fixtures not found" unless Dir.exist?(FIXTURES_DIR)
  end

  describe "Decoding official good files" do
    # Test that we can decode all official good-*.xz files
    Dir.glob(File.join(FIXTURES_DIR, "good-*.xz")).each do |test_file|
      it "decodes #{File.basename(test_file)}" do
        # First verify xz can decode it (sanity check)
        reference = `xz -dc #{test_file} 2>&1`
        expect($?.success?).to eq(true), "Reference xz failed: #{reference}"

        # Now test our decoder (when implemented)
        # For now, just verify the file exists and has valid structure
        expect(File.exist?(test_file)).to be true
        expect(File.size(test_file)).to be > 0
      end
    end
  end

  describe "Encoding compatibility tests" do
    after(:each) do
      FileUtils.rm_f("test_output.xz")
    end

    {
      "empty" => "",
      "single_byte" => "a",
      "hello_world" => "Hello World!",
      "short_text" => "The quick brown fox",
      "newlines" => "Line 1\nLine 2\nLine 3\n",
      "repeated" => "a" * 100,
      "binary" => (0..255).to_a.pack("C*"),
    }.each do |name, data|
      it "creates xz-compatible file for #{name}" do
        Omnizip::Formats::Xz::Writer.create("test_output.xz") do |xz|
          xz.add_data(data)
        end

        # Verify with xz -dc
        output = `xz -dc test_output.xz 2>&1`
        exit_code = $?.exitstatus

        if exit_code != 0
          # Dump hex for debugging
          hex = `xxd test_output.xz | head -20`.strip
          puts "\n=== Test: #{name} ==="
          puts "Expected: #{data.inspect}"
          puts "XZ error: #{output}"
          puts "\nFirst 20 lines of hex:\n#{hex}"

          # Compare with reference
          if File.exist?(File.join(FIXTURES_DIR, "good-1-check-crc64.xz"))
            ref_hex = `xxd #{FIXTURES_DIR}/good-1-check-crc64.xz | head -20`.strip
            puts "\nReference file hex:\n#{ref_hex}"
          end
        end

        expect(exit_code).to eq(0), "xz -dc failed with: #{output}"
        expect(output).to eq(data) unless data.encoding == Encoding::ASCII_8BIT
        expect(output.bytes).to eq(data.bytes) if data.encoding == Encoding::ASCII_8BIT
      end
    end
  end

  describe "Structure comparison with official files" do
    it "compares our output structure with good-1-check-crc64.xz" do
      reference_file = File.join(FIXTURES_DIR, "good-1-check-crc64.xz")
      skip "Reference file not found" unless File.exist?(reference_file)

      # Decode reference to get original data
      reference_data = `xz -dc #{reference_file} 2>&1`
      expect($?.success?).to be true

      # Create our version
      Omnizip::Formats::Xz::Writer.create("test_output.xz") do |xz|
        xz.add_data(reference_data)
      end

      # Compare structures
      our_hex = File.read("test_output.xz").bytes
      ref_hex = File.read(reference_file).bytes

      puts "\n=== Structure Comparison ==="
      puts "Reference size: #{ref_hex.size} bytes"
      puts "Our size: #{our_hex.size} bytes"

      # Compare headers
      puts "\nStream Header (12 bytes):"
      puts "Ref: #{ref_hex[0..11].map { |b| sprintf('%02X', b) }.join(' ')}"
      puts "Our: #{our_hex[0..11].map { |b| sprintf('%02X', b) }.join(' ')}"

      # Find differences
      differences = []
      [our_hex.size, ref_hex.size].min.times do |i|
        if our_hex[i] != ref_hex[i]
          differences << {
            offset: i,
            ref: ref_hex[i],
            our: our_hex[i],
          }
        end
      end

      if differences.any?
        puts "\nFirst 10 differences:"
        differences.first(10).each do |diff|
          puts sprintf("Offset 0x%04X: Ref=%02X Our=%02X",
                       diff[:offset], diff[:ref], diff[:our])
        end
      end

      FileUtils.rm_f("test_output.xz")
    end
  end

  describe "LZMA2 chunk type analysis" do
    it "analyzes LZMA2 chunk types in official files" do
      # Analyze good files to understand LZMA2 chunk patterns
      test_files = [
        "good-1-check-crc64.xz",
        "good-1-lzma2-1.xz",
        "good-1-lzma2-3.xz", # Has uncompressed chunk
      ]

      test_files.each do |filename|
        filepath = File.join(FIXTURES_DIR, filename)
        next unless File.exist?(filepath)

        data = File.read(filepath).bytes

        # Skip to LZMA2 stream (after headers)
        # Stream header: 12 bytes
        # Block header: variable, starts at offset 12

        # Find block header end (look for LZMA2 control byte patterns)
        offset = 12
        block_header_size = (data[offset] * 4) + 4 # First byte * 4 + 4
        lzma2_start = offset + block_header_size

        puts "\n=== #{filename} ==="
        puts "LZMA2 starts at offset: #{lzma2_start}"

        # Read first few LZMA2 control bytes
        5.times do |i|
          ctrl_offset = lzma2_start + i
          break if ctrl_offset >= data.size

          ctrl = data[ctrl_offset]
          if ctrl == 0x00
            puts "  Offset #{ctrl_offset}: END (0x00)"
            break
          elsif ctrl == 0x01
            puts "  Offset #{ctrl_offset}: UNCOMPRESSED, dict reset (0x01)"
          elsif ctrl == 0x02
            puts "  Offset #{ctrl_offset}: UNCOMPRESSED, no dict reset (0x02)"
          elsif ctrl >= 0x80
            puts "  Offset #{ctrl_offset}: LZMA compressed (0x#{ctrl.to_s(16).upcase})"
          end
        end
      end
    end
  end
end
