# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "XZ Format Compatibility" do
  describe "xz -dc compatibility" do
    after(:each) do
      # Clean up test files
      FileUtils.rm_f("test.xz")
      FileUtils.rm_f("decoded.txt")
    end

    it "produces simple file decodable by xz -dc" do
      data = "a"

      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      # Decompress with xz -dc
      output = `xz -dc test.xz 2>&1`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0), "xz -dc failed: #{output}"
      expect(output).to eq(data)
    end

    it "handles Hello World" do
      data = "Hello World!"

      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      output = `xz -dc test.xz 2>&1`
      expect($?.success?).to be true
      expect(output).to eq(data)
    end

    it "handles various input sizes" do
      [10, 100, 1000].each do |size|
        data = "a" * size

        Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
          xz.add_data(data)
        end

        output = `xz -dc test.xz 2>&1`
        expect($?.success?).to be true
        expect(output).to eq(data)
      end
    end

    it "handles binary data" do
      data = (0..255).to_a.pack("C*") * 10

      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      output = `xz -dc test.xz 2>&1`
      expect($?.success?).to be true
      expect(output.bytes).to eq(data.bytes)
    end

    it "handles text with newlines" do
      data = "Line 1\nLine 2\nLine 3\n"

      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      output = `xz -dc test.xz 2>&1`
      expect($?.success?).to be true
      expect(output).to eq(data)
    end

    it "round-trip works (Omnizip → xz → Omnizip)" do
      data = "The quick brown fox jumps over the lazy dog"

      # Omnizip encode
      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      # xz decode
      system("xz -dc test.xz > decoded.txt 2>&1")
      expect($?.success?).to be true

      decoded = File.read("decoded.txt")
      expect(decoded).to eq(data)
    end

    it "can be inspected with xz -l" do
      data = "Test data for inspection"

      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data(data)
      end

      # List archive contents
      output = `xz -l test.xz 2>&1`
      expect($?.success?).to be true
      expect(output).to include("test.xz")
    end
  end

  describe "XZ Writer API" do
    it "creates valid XZ file" do
      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data("test")
      end

      expect(File.exist?("test.xz")).to be true
      FileUtils.rm_f("test.xz")
    end

    it "writes correct magic bytes" do
      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data("test")
      end

      File.open("test.xz", "rb") do |f|
        magic = f.read(6).bytes
        expect(magic).to eq([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
      end

      FileUtils.rm_f("test.xz")
    end

    it "handles empty data" do
      Omnizip::Formats::Xz::Writer.create("test.xz") do |xz|
        xz.add_data("")
      end

      output = `xz -dc test.xz 2>&1`
      expect($?.success?).to be true
      expect(output).to eq("")

      FileUtils.rm_f("test.xz")
    end
  end
end
