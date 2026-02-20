# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Tool Compatibility", :tool_integration do
  # Test XZ Utils tool (xz command) compatibility
  # Reference: Official XZ Utils source at /Users/mulgogi/src/external/xz
  describe "XZ Utils (xz command)" do
    let(:test_fixtures_dir) do
      File.join(File.dirname(__FILE__), "../fixtures/xz_utils")
    end
    let(:test_data) do
      "Hello, XZ Utils! This is a test for tool compatibility." * 100
    end
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
    end

    describe "decompression" do
      it "can decompress files created by xz command" do
        skip "xz command not available" unless system("which xz > /dev/null 2>&1")

        # Create a file using xz command
        test_file = File.join(temp_dir, "test.txt")
        xz_file = File.join(temp_dir, "test.txt.xz")

        File.write(test_file, test_data)
        system("xz -z #{test_file.shellescape}")

        # Try to decompress with our implementation
        reader = Omnizip::Formats::Xz::Reader.new(xz_file)
        decompressed = reader.read

        expect(decompressed).to eq(test_data)
      end

      it "can decompress XZ Utils test fixtures" do
        skip "xz command not available" unless system("which xz > /dev/null 2>&1")

        test_files = Dir.glob(File.join(test_fixtures_dir,
                                        "good/good-1-lzma2-*.xz"))

        test_files.each do |xz_file|
          basename = File.basename(xz_file)

          # First verify xz can decompress it
          temp_decompressed = File.join(temp_dir, "#{basename}.decompressed")
          system("xz -d -c #{xz_file.shellescape} > #{temp_decompressed.shellescape}")
          xz_decompressed = File.binread(temp_decompressed)

          # Now try our decoder
          reader = Omnizip::Formats::Xz::Reader.new(xz_file)
          our_decompressed = reader.read

          expect(our_decompressed).to eq(xz_decompressed),
                                      "Our decoder should match xz output for #{basename}"
        end
      end
    end

    describe "compression" do
      it "creates files that xz command can decompress" do
        skip "xz command not available" unless system("which xz > /dev/null 2>&1")

        # Create XZ file with our implementation
        xz_file = File.join(temp_dir, "test.xz")
        Omnizip::Formats::Xz.create(test_data, xz_file)

        # Try to decompress with xz command
        temp_decompressed = File.join(temp_dir, "test.txt.decompressed")
        system("xz -d -c #{xz_file.shellescape} > #{temp_decompressed.shellescape}")

        xz_decompressed = File.binread(temp_decompressed)

        # Decompress with our implementation for comparison
        reader = Omnizip::Formats::Xz::Reader.new(xz_file)
        our_decompressed = reader.read

        expect(xz_decompressed).to eq(test_data),
                                   "xz should decompress to original data"
        expect(our_decompressed).to eq(test_data),
                                    "Our decoder should decompress to original data"
      end
    end
  end

  # Test 7-Zip tool (7zz command) compatibility
  # Reference: Official 7-Zip source at /Users/mulgogi/src/external/7-Zip
  # NOTE: We focus on official 7-Zip (7zz), NOT p7zip which is deprecated
  describe "7-Zip (7zz command)" do
    let(:test_data) do
      "Hello, 7-Zip! This is a test for tool compatibility." * 100
    end
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
    end

    describe "decompression" do
      it "can decompress files created by 7zz command" do
        skip "7zz command not available" unless system("which 7zz > /dev/null 2>&1")

        # Create a 7z file using 7zz command
        test_file = File.join(temp_dir, "test.txt")
        seven_zip_file = File.join(temp_dir, "test.7z")

        File.write(test_file, test_data)
        system("7zz a #{seven_zip_file.shellescape} #{test_file.shellescape} > /dev/null")

        # Try to decompress with our implementation
        reader = Omnizip::Formats::SevenZip::Reader.new(seven_zip_file)
        reader.open
        files = reader.list_files

        expect(files).not_to be_empty

        files.each do |file|
          # Extract to temp file
          extract_path = File.join(temp_dir,
                                   "extracted_#{File.basename(file.name)}")
          reader.extract_entry(file.name, extract_path)
          content = File.binread(extract_path)
          expect(content).to eq(test_data),
                             "Extracted content should match original"
        end
      end
    end

    describe "compression" do
      it "creates files that 7zz command can decompress" do
        skip "7zz command not available" unless system("which 7zz > /dev/null 2>&1")

        # Create 7z file with our implementation
        seven_zip_file = File.join(temp_dir, "test.7z")
        Omnizip::Formats::SevenZip.create(seven_zip_file) do |zip|
          zip.add_data("test.txt", test_data)
        end

        # Try to list with 7zz command
        list_output = `7zz l #{seven_zip_file.shellescape} 2>&1`
        expect(list_output).to include("test.txt")

        # Try to decompress with 7zz command
        extract_dir = File.join(temp_dir, "extracted")
        FileUtils.mkdir_p(extract_dir)
        system("cd #{extract_dir.shellescape} && 7zz x #{seven_zip_file.shellescape} > /dev/null 2>&1")

        extracted_file = File.join(extract_dir, "test.txt")
        expect(File).to exist(extracted_file)

        seven_zip_decompressed = File.binread(extracted_file)
        expect(seven_zip_decompressed).to eq(test_data),
                                          "7zz should decompress to original data"

        # Also verify our implementation can decompress
        reader = Omnizip::Formats::SevenZip::Reader.new(seven_zip_file)
        reader.open
        files = reader.list_files

        our_decompressed = nil
        files.each do |file|
          # Extract to temp file
          extract_path = File.join(temp_dir,
                                   "our_extracted_#{File.basename(file.name)}")
          reader.extract_entry(file.name, extract_path)
          our_decompressed = File.binread(extract_path)
        end

        expect(our_decompressed).to eq(test_data),
                                    "Our decoder should decompress to original data"
      end
    end
  end

  # LZMA2 format-specific tests
  describe "LZMA2 encoder compatibility" do
    let(:test_data) { "Test data for LZMA2 compression!" * 50 }
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
    end

    describe "XZ Utils LZMA2 encoder" do
      it "produces valid LZMA2 output that round-trips with our decoder" do
        encoder = Omnizip::Implementations::XZUtils::LZMA2::Encoder.new(
          dict_size: 8192,
          lc: 3,
          lp: 0,
          pb: 2,
          standalone: true,
        )

        compressed = encoder.encode(test_data)

        # Verify we can round-trip with our own decoder
        require "stringio"
        input = StringIO.new(compressed)
        input.set_encoding(Encoding::BINARY)

        decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(
          input,
          raw_mode: false, # standalone mode - read property byte from stream
        )
        decompressed = decoder.decode_stream

        expect(decompressed).to eq(test_data)
      end
    end

    describe "7-Zip LZMA2 encoder" do
      it "produces valid LZMA2 output (no standalone property byte)" do
        encoder = Omnizip::Implementations::SevenZip::LZMA2::Encoder.new(
          dict_size: 8192,
          lc: 3,
          lp: 0,
          pb: 2,
          standalone: false,
        )

        compressed = encoder.encode(test_data)

        # Verify it starts with compressed chunk (0xE0 or similar)
        # and ends with end marker (0x00)
        expect(compressed.bytesize).to be > 0
        expect(compressed.getbyte(0) & 0x80).to eq(0x80),
                                                "Should start with compressed chunk"
        expect(compressed.getbyte(-1)).to eq(0x00), "Should end with EOS marker"

        # Verify we can round-trip
        require "stringio"
        input = StringIO.new(compressed)
        input.set_encoding(Encoding::BINARY)

        decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(
          input,
          raw_mode: true,
          dict_size: 8192,
        )
        decompressed = decoder.decode_stream

        expect(decompressed).to eq(test_data)
      end
    end
  end
end
