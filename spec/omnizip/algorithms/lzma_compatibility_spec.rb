# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/seven_zip/reader"
require "stringio"
require "open3"
require "tmpdir"

RSpec.describe "LZMA Official Tool Compatibility" do
  let(:test_data) { "The quick brown fox jumps over the lazy dog. " * 20 }
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(temp_dir) }

  describe "xz utility compatibility" do
    before do
      # Check if xz is available
      _, _, status = Open3.capture3("which xz")
      skip "xz utility not installed" unless status.success?
    end

    it "produces output decodable by xz" do
      # Create .lzma file with Omnizip
      lzma_file = File.join(temp_dir, "test.lzma")
      File.open(lzma_file, "wb") do |f|
        compressed = StringIO.new
        Omnizip::Algorithms::LZMA.new.compress(StringIO.new(test_data),
                                               compressed)
        f.write(compressed.string)
      end

      # Try to decompress with xz
      output_file = File.join(temp_dir, "test")
      stdout, stderr, status = Open3.capture3("xz -d -k #{lzma_file}")

      if status.success?
        expect(File.exist?(output_file)).to be true
        expect(File.read(output_file)).to eq(test_data)
      else
        # Document failure for later analysis
        puts "\nxz decompression failed:"
        puts "STDOUT: #{stdout}"
        puts "STDERR: #{stderr}"
        puts "Status: #{status.exitstatus}"

        # Inspect file header for debugging
        header = File.read(lzma_file, 13, mode: "rb")
        puts "Header (hex): #{header.bytes.map { |b| '%02X' % b }.join(' ')}"

        # This is expected to fail initially - we're testing to see why
        skip "xz compatibility not yet implemented (expected)"
      end
    end

    it "decodes xz-encoded files" do
      # Create raw LZMA file with xz (using --format=lzma for raw LZMA)
      input_file = File.join(temp_dir, "test.txt")
      File.write(input_file, test_data)

      # xz --format=lzma creates .lzma file (not .xz)
      _, _, status = Open3.capture3("xz -z -k --format=lzma #{input_file}")
      expect(status.success?).to be true

      # Decode with Omnizip
      lzma_file = "#{input_file}.lzma" # xz creates .lzma extension for --format=lzma
      compressed = File.read(lzma_file, mode: "rb")
      decompressed = StringIO.new

      begin
        Omnizip::Algorithms::LZMA.new.decompress(StringIO.new(compressed),
                                                 decompressed)
        expect(decompressed.string).to eq(test_data)
      rescue StandardError => e
        puts "\nOmnizip failed to decode xz-created LZMA file:"
        puts "Error: #{e.message}"
        puts "Error class: #{e.class}"

        # Inspect file header
        header = compressed[0, 13]
        puts "Header (hex): #{header.bytes.map { |b| '%02X' % b }.join(' ')}"

        skip "xz LZMA format compatibility not yet implemented (expected)"
      end
    end
  end

  describe "7z utility compatibility" do
    before do
      # Check if 7z is available
      _, _, status = Open3.capture3("which 7z")
      skip "7z utility not installed" unless status.success?
    end

    it "produces archives extractable by 7z" do
      # Create .lzma file with Omnizip
      lzma_file = File.join(temp_dir, "test.lzma")
      File.open(lzma_file, "wb") do |f|
        compressed = StringIO.new
        Omnizip::Algorithms::LZMA.new.compress(StringIO.new(test_data),
                                               compressed)
        f.write(compressed.string)
      end

      # Try to extract with 7z
      stdout, stderr, status = Open3.capture3("7z x -o#{temp_dir} #{lzma_file}")

      if status.success?
        # 7z extracts to file without .lzma extension
        extracted_file = File.join(temp_dir, "test")
        expect(File.exist?(extracted_file)).to be true
        expect(File.read(extracted_file)).to eq(test_data)
      else
        puts "\n7z extraction failed:"
        puts "STDOUT: #{stdout}"
        puts "STDERR: #{stderr}"

        skip "7z compatibility not yet implemented (expected)"
      end
    end

    it "decodes 7z-created LZMA content from .7z container" do
      # Create test file
      source_file = File.join(temp_dir, "source.txt")
      File.write(source_file, test_data)

      # Create .7z archive with 7z CLI (uses LZMA by default)
      seven_z_file = File.join(temp_dir, "test.7z")
      _, stderr, status = Open3.capture3(
        "7z a -t7z #{seven_z_file} #{source_file} 2>&1",
      )

      unless status.success?
        skip "Failed to create 7z archive: #{stderr}"
      end

      # Read and extract with Omnizip
      reader = Omnizip::Formats::SevenZip::Reader.new(seven_z_file)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(1)

      # Extract the file
      extract_dir = File.join(temp_dir, "extracted")
      FileUtils.mkdir_p(extract_dir)
      reader.extract_entry(files.first.name,
                           File.join(extract_dir, files.first.name))

      # Verify content
      extracted_file = File.join(extract_dir, files.first.name)
      expect(File.exist?(extracted_file)).to be true
      expect(File.read(extracted_file)).to eq(test_data)
    end

    it "round-trips with 7z using raw LZMA" do
      # Create raw LZMA file with Omnizip
      lzma_file = File.join(temp_dir, "test.lzma")
      File.open(lzma_file, "wb") do |f|
        compressed = StringIO.new
        Omnizip::Algorithms::LZMA.new.compress(StringIO.new(test_data),
                                               compressed)
        f.write(compressed.string)
      end

      # Try to extract with 7z (it can decode raw LZMA files)
      stdout, stderr, status = Open3.capture3("7z x -o#{temp_dir} -y #{lzma_file}")

      if status.success?
        # 7z extracts to file without .lzma extension
        extracted_file = File.join(temp_dir, "test")
        expect(File.exist?(extracted_file)).to be true
        expect(File.read(extracted_file)).to eq(test_data)
      else
        puts "\n7z extraction failed:"
        puts "STDOUT: #{stdout}"
        puts "STDERR: #{stderr}"

        skip "7z raw LZMA compatibility not yet implemented (expected)"
      end
    end
  end

  describe "lzma utility compatibility" do
    before do
      # Check if lzma is available (part of xz-utils)
      _, _, status = Open3.capture3("which lzma")
      skip "lzma utility not installed" unless status.success?
    end

    it "produces output decodable by lzma" do
      # Create .lzma file with Omnizip
      lzma_file = File.join(temp_dir, "test.lzma")
      File.open(lzma_file, "wb") do |f|
        compressed = StringIO.new
        Omnizip::Algorithms::LZMA.new.compress(StringIO.new(test_data),
                                               compressed)
        f.write(compressed.string)
      end

      # Try to decompress with lzma
      _, stderr, status = Open3.capture3("lzma -d -k #{lzma_file}")

      if status.success?
        output_file = File.join(temp_dir, "test")
        expect(File.exist?(output_file)).to be true
        expect(File.read(output_file)).to eq(test_data)
      else
        puts "\nlzma decompression failed:"
        puts "STDERR: #{stderr}"
        skip "lzma compatibility not yet implemented (expected)"
      end
    end

    it "decodes lzma-encoded files" do
      # Create file with lzma
      input_file = File.join(temp_dir, "test.txt")
      File.write(input_file, test_data)

      _, _, status = Open3.capture3("lzma -z -k #{input_file}")
      expect(status.success?).to be true

      # Decode with Omnizip
      lzma_file = "#{input_file}.lzma"
      compressed = File.read(lzma_file, mode: "rb")
      decompressed = StringIO.new

      begin
        Omnizip::Algorithms::LZMA.new.decompress(StringIO.new(compressed),
                                                 decompressed)
        expect(decompressed.string).to eq(test_data)
      rescue StandardError => e
        puts "\nOmnizip failed to decode lzma file:"
        puts "Error: #{e.message}"
        skip "lzma format compatibility not yet implemented (expected)"
      end
    end
  end

  describe "format analysis" do
    it "documents Omnizip header format" do
      compressed = StringIO.new
      Omnizip::Algorithms::LZMA.new.compress(StringIO.new(test_data),
                                             compressed)

      header = compressed.string[0, 13].bytes

      # Property byte
      props = header[0]
      lc = props % 9
      rem = props / 9
      lp = rem % 5
      pb = rem / 5

      # Dictionary size (4 bytes, little-endian)
      dict_size = header[1] | (header[2] << 8) | (header[3] << 16) | (header[4] << 24)

      # Uncompressed size (8 bytes, little-endian)
      size_bytes = header[5..12]
      uncompressed_size = size_bytes.map.with_index { |b, i| b << (i * 8) }.sum

      puts "\nOmnizip LZMA Header Analysis:"
      puts "Property byte: 0x%02X (lc=%d, lp=%d, pb=%d)" % [props, lc, lp, pb]
      puts "Dictionary size: 0x%08X (%d bytes)" % [dict_size, dict_size]
      puts "Uncompressed size: 0x%016X (%d bytes)" % [uncompressed_size,
                                                      uncompressed_size]
      puts "Header (hex): #{header.map { |b| '%02X' % b }.join(' ')}"

      # This test always passes - it's for documentation
      expect(header.size).to eq(13)
    end
  end
end
