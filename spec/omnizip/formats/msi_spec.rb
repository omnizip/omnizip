# frozen_string_literal: true

require "spec_helper"
require "csv"
require "tmpdir"

RSpec.describe Omnizip::Formats::Msi do
  let(:fixtures_dir) { "spec/fixtures/lessmsi" }
  let(:msi_input_dir) { "#{fixtures_dir}/MsiInput" }
  let(:expected_output_dir) { "#{fixtures_dir}/ExpectedOutput" }

  describe ".open" do
    it "opens and yields reader" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"

      described_class.open(msi_path) do |msi|
        expect(msi).to be_a(Omnizip::Formats::Msi::Reader)
        expect(msi.files).to be_an(Array)
        expect(msi.files.size).to be > 0
      end
    end

    it "returns reader without block" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"

      reader = described_class.open(msi_path)
      begin
        expect(reader).to be_a(Omnizip::Formats::Msi::Reader)
      ensure
        reader.close
      end
    end
  end

  describe ".list" do
    it "lists files in putty MSI" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"

      files = described_class.list(msi_path)

      expect(files).to be_an(Array)
      expect(files.size).to eq(10) # PuTTY has 10 files
      expect(files.first).to include("SourceDir")
    end
  end

  describe ".info" do
    it "returns package info" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"

      info = described_class.info(msi_path)

      expect(info).to be_a(Hash)
      expect(info[:path]).to eq(msi_path)
      expect(info[:file_count]).to eq(10)
      expect(info[:tables]).to be_an(Array)
      expect(info[:tables]).to include("File")
      expect(info[:tables]).to include("Component")
      expect(info[:tables]).to include("Directory")
    end
  end

  describe ".extract" do
    it "extracts putty MSI matching lessmsi expected output" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"
      expected_csv = "#{expected_output_dir}/putty-0.68-installer.msi.expected.csv"

      Dir.mktmpdir("msi_test") do |output_dir|
        described_class.extract(msi_path, output_dir)

        # Verify files extracted
        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to be > 0

        # Compare with expected output
        expected = CSV.read(expected_csv)
        expected_paths = expected[1..].map do |row|
          row[0].gsub("\\", "/").sub(/^\\SourceDir\//, "")
        end

        actual_paths = files.map do |f|
          f.sub("#{output_dir}/", "")
        end

        # Check that we have the same number of files
        expect(actual_paths.size).to eq(expected_paths.size)

        # Check that all expected files are present
        expected_paths.each do |expected_path|
          matching = actual_paths.any? do |actual|
            actual.end_with?(expected_path) || expected_path.end_with?(actual)
          end
          expect(matching).to be_truthy,
                              "Expected file not found: #{expected_path}"
        end
      end
    end

    it "extracts NUnit MSI" do
      msi_path = "#{msi_input_dir}/NUnit-2.5.2.9222.msi"

      skip "NUnit MSI not available" unless File.exist?(msi_path)

      Dir.mktmpdir("msi_test") do |output_dir|
        described_class.extract(msi_path, output_dir)

        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to be > 0
      end
    end

    it "handles external CAB files" do
      msi_path = "#{msi_input_dir}/msi_with_external_cab.msi"
      cab_path = "#{msi_input_dir}/msi_with_external_cab.cab"

      skip "External CAB test files not available" unless File.exist?(msi_path) && File.exist?(cab_path)

      Dir.mktmpdir("msi_test") do |output_dir|
        described_class.extract(msi_path, output_dir)

        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to be > 0
      end
    end

    it "handles path with spaces" do
      msi_path = "#{msi_input_dir}/Path With Spaces/spaces example.msi"

      skip "Path with spaces test file not available" unless File.exist?(msi_path)

      Dir.mktmpdir("msi_test") do |output_dir|
        described_class.extract(msi_path, output_dir)

        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to be > 0
      end
    end
  end

  describe "Entry" do
    it "has correct file metadata" do
      msi_path = "#{msi_input_dir}/putty-0.68-installer.msi"

      described_class.open(msi_path) do |msi|
        entry = msi.entries.first

        expect(entry).to be_a(Omnizip::Formats::Msi::Entry)
        expect(entry.path).to be_a(String)
        expect(entry.size).to be_an(Integer)
        expect(entry.sequence).to be_an(Integer)
        expect(entry.file?).to be true
        expect(entry.directory?).to be false
      end
    end

    it "parses filename with short and long names" do
      entry = Omnizip::Formats::Msi::Entry.new
      entry.parse_filename("shortna~1.txt|longname.txt")

      expect(entry.short_name).to eq("shortna~1.txt")
      expect(entry.long_name).to eq("longname.txt")
      expect(entry.display_name).to eq("longname.txt")
    end

    it "parses filename without short name" do
      entry = Omnizip::Formats::Msi::Entry.new
      entry.parse_filename("simple.txt")

      expect(entry.short_name).to be_nil
      expect(entry.long_name).to eq("simple.txt")
      expect(entry.display_name).to eq("simple.txt")
    end
  end

  describe "format registration" do
    it "registers .msi extension" do
      expect(Omnizip::FormatRegistry.supported?(".msi")).to be true
    end

    it "registers .msp extension" do
      expect(Omnizip::FormatRegistry.supported?(".msp")).to be true
    end

    it "overrides OLE's .msi registration" do
      handler = Omnizip::FormatRegistry.get(".msi")
      expect(handler).to eq(Omnizip::Formats::Msi)
    end
  end
end
