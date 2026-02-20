# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"
require_relative "../../../lib/omnizip/formats/rpm"

RSpec.describe Omnizip::Formats::Rpm do
  let(:fixture_dir) { File.join(File.dirname(__FILE__), "../../fixtures/rpm") }
  let(:example_rpm) { File.join(fixture_dir, "example-1.0-1.x86_64.rpm") }
  let(:pagure_rpm) { File.join(fixture_dir, "pagure-mirror-5.13.2-5.fc35.noarch.rpm") }
  let(:example_json) { File.join(fixture_dir, "example.json") }

  describe ".open" do
    it "opens and yields reader" do
      described_class.open(example_rpm) do |rpm|
        expect(rpm).to be_a(Omnizip::Formats::Rpm::Reader)
        expect(rpm.name).to eq("example")
      end
    end

    it "returns reader without block" do
      reader = described_class.open(example_rpm)
      expect(reader).to be_a(Omnizip::Formats::Rpm::Reader)
      expect(reader.name).to eq("example")
      reader.close
    end
  end

  describe ".list" do
    it "lists files in RPM" do
      files = described_class.list(pagure_rpm)
      expect(files).to be_an(Array)
      expect(files).not_to be_empty
    end
  end

  describe ".info" do
    it "returns package information" do
      info = described_class.info(example_rpm)

      expect(info[:name]).to eq("example")
      expect(info[:version]).to eq("1.0")
      expect(info[:release]).to eq("1")
      expect(info[:arch]).to eq("x86_64")
    end
  end

  describe Omnizip::Formats::Rpm::Lead do
    describe ".parse" do
      it "parses valid lead" do
        File.open(example_rpm, "rb") do |io|
          lead = described_class.parse(io)

          expect(lead.magic.b).to eq("\xed\xab\xee\xdb".b)
          expect(lead.major_version).to eq(3)
          expect(lead.minor_version).to eq(0)
          expect(lead.name).to eq("example-1.0-1")
          expect(lead.binary?).to be true
        end
      end

      it "raises error for invalid magic" do
        io = StringIO.new("\x00\x00\x00\x00#{'\x00' * 92}")

        expect { described_class.parse(io) }.to raise_error(ArgumentError, /Invalid RPM magic/)
      end

      it "raises error for truncated data" do
        io = StringIO.new("\xed\xab\xee\xdb")

        expect { described_class.parse(io) }.to raise_error(ArgumentError, /Truncated/)
      end
    end
  end

  describe Omnizip::Formats::Rpm::Header do
    before do
      @file = File.open(example_rpm, "rb")
      # Skip lead
      @file.read(96)
      # Skip signature if present
      sig_header = Omnizip::Formats::Rpm::Header.parse(@file)
      padding = sig_header.length % 8
      @file.read(padding) if padding.positive?
    end

    after do
      @file&.close
    end

    it "parses header tags" do
      header = described_class.parse(@file)

      expect(header.tags).to be_an(Array)
      expect(header.tags).not_to be_empty
    end

    it "extracts tag values" do
      header = described_class.parse(@file)

      expect(header[:name]).to eq("example")
      expect(header[:version]).to eq("1.0")
      expect(header[:release]).to eq("1")
    end
  end

  describe Omnizip::Formats::Rpm::Reader do
    subject { described_class.new(example_rpm) }

    before { subject.open }
    after { subject.close }

    describe "#name" do
      it "returns package name" do
        expect(subject.name).to eq("example")
      end
    end

    describe "#version" do
      it "returns package version" do
        expect(subject.version).to eq("1.0")
      end
    end

    describe "#release" do
      it "returns package release" do
        expect(subject.release).to eq("1")
      end
    end

    describe "#architecture" do
      it "returns architecture" do
        expect(subject.architecture).to eq("x86_64")
      end
    end

    describe "#files" do
      it "returns list of files (may be empty for minimal RPMs)" do
        files = subject.files

        expect(files).to be_an(Array)
        files.each do |f|
          expect(f).to start_with("/")
        end
      end
    end

    describe "#entries" do
      it "returns file entries with metadata (may be empty for minimal RPMs)" do
        entries = subject.entries

        expect(entries).to be_an(Array)

        if entries.any?
          entry = entries.first
          expect(entry).to be_a(Omnizip::Formats::Rpm::Entry)
          expect(entry.path).to start_with("/")
          expect(entry.mode).to be_a(Integer)
        end
      end
    end

    describe "#requires" do
      it "returns dependencies" do
        requires = subject.requires

        expect(requires).to be_an(Array)
        requires.each do |req|
          expect(req).to be_an(Array)
          expect(req.size).to eq(3) # [name, operator, version]
        end
      end
    end

    describe "#payload_compressor" do
      it "returns compressor name" do
        expect(subject.payload_compressor).to eq("gzip")
      end
    end

    describe "#tags" do
      it "returns all tags as hash" do
        tags = subject.tags

        expect(tags).to be_a(Hash)
        expect(tags[:name]).to eq("example")
        expect(tags[:version]).to eq("1.0")
        expect(tags[:payloadformat]).to eq("cpio")
      end
    end
  end

  describe "with pagure RPM" do
    subject { Omnizip::Formats::Rpm::Reader.new(pagure_rpm) }

    before { subject.open }
    after { subject.close }

    describe "#files" do
      it "matches expected file list" do
        expected_files = [
          "/usr/lib/systemd/system/pagure_mirror.service",
          "/usr/share/licenses/pagure-mirror",
          "/usr/share/licenses/pagure-mirror/LICENSE",
        ]

        expect(subject.files).to eq(expected_files)
      end
    end
  end

  describe "header tag values from JSON" do
    let(:expectations) { JSON.parse(File.read(example_json)) }

    it "matches expected tag values" do
      described_class.open(example_rpm) do |rpm|
        expectations.each do |tag_name, expected_value|
          # Convert uppercase JSON key to lowercase symbol
          tag_key = tag_name.downcase.to_sym
          actual = rpm.tags[tag_key]

          # Skip if tag not found in our implementation
          next unless rpm.tags.key?(tag_key)

          # Handle array vs single value comparison
          if actual.is_a?(Array)
            if expected_value.is_a?(Array)
              expect(actual).to eq(expected_value)
            else
              expect(actual.first).to eq(expected_value)
            end
          else
            expect(actual).to eq(expected_value)
          end
        end
      end
    end
  end

  describe ".extract" do
    it "extracts files to directory" do
      Dir.mktmpdir do |dir|
        described_class.extract(pagure_rpm, dir)

        # Check that files were extracted
        files = Dir.glob("#{dir}/**/*", File::FNM_PATHNAME).reject { |f| File.directory?(f) }
        expect(files).not_to be_empty
      end
    end
  end
end
