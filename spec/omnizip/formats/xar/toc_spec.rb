# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Xar::Toc do
  describe "#initialize" do
    it "creates an empty TOC" do
      toc = described_class.new

      expect(toc.entries).to be_empty
      expect(toc.checksum_style).to eq("sha1")
    end
  end

  describe "#add_entry" do
    it "adds an entry to the TOC" do
      toc = described_class.new
      entry = Omnizip::Formats::Xar::Entry.new("test.txt")

      toc.add_entry(entry)

      expect(toc.entries.size).to eq(1)
      expect(toc.entries.first.name).to eq("test.txt")
    end

    it "assigns an ID to entries" do
      toc = described_class.new
      entry = Omnizip::Formats::Xar::Entry.new("test.txt")

      toc.add_entry(entry)

      expect(entry.id).to eq(1)
    end
  end

  describe "#to_xml_string" do
    it "generates valid XML" do
      toc = described_class.new
      entry = Omnizip::Formats::Xar::Entry.new("test.txt", type: "file")
      entry.data_size = 100
      entry.data_offset = 0
      entry.data_length = 50
      entry.mode = 0o644
      toc.add_entry(entry)

      xml = toc.to_xml_string

      # REXML uses single quotes for attributes
      expect(xml).to include("<?xml version='1.0' encoding='UTF-8'?>")
      expect(xml).to include("<xar>")
      expect(xml).to include("<toc>")
      expect(xml).to include("test.txt")
      expect(xml).to include("file")
    end

    it "includes checksum information" do
      toc = described_class.new
      toc.checksum_style = "sha1"
      toc.checksum_offset = 0
      toc.checksum_size = 20

      xml = toc.to_xml_string

      # REXML uses single quotes for attributes
      expect(xml).to include("style='sha1'")
    end
  end

  describe "#compress and .decompress" do
    it "compresses and decompresses TOC XML" do
      toc = described_class.new
      entry = Omnizip::Formats::Xar::Entry.new("test.txt")
      toc.add_entry(entry)

      compressed = toc.compress
      uncompressed = described_class.decompress(compressed)

      expect(uncompressed).to include("<xar>")
      expect(uncompressed).to include("test.txt")
    end
  end

  describe ".from_xml" do
    it "parses XML with a single file entry" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xar>
          <toc>
            <creation-time>1609459200.0</creation-time>
            <checksum style="sha1">
              <offset>0</offset>
              <size>20</size>
            </checksum>
            <file id="1">
              <name>test.txt</name>
              <type>file</type>
              <mode>0644</mode>
              <data>
                <offset>0</offset>
                <size>50</size>
                <length>100</length>
                <encoding style="application/x-gzip"/>
              </data>
            </file>
          </toc>
        </xar>
      XML

      doc = REXML::Document.new(xml)
      toc = described_class.from_xml(doc)

      expect(toc.entries.size).to eq(1)
      expect(toc.entries.first.name).to eq("test.txt")
      expect(toc.entries.first.type).to eq("file")
      expect(toc.entries.first.mode).to eq(0o644)
      expect(toc.entries.first.data_encoding).to eq("gzip")
    end

    it "parses file with symlink" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xar>
          <toc>
            <file id="1">
              <name>symlink</name>
              <type>symlink</type>
              <link type="symbolic">target.txt</link>
            </file>
          </toc>
        </xar>
      XML

      doc = REXML::Document.new(xml)
      toc = described_class.from_xml(doc)

      expect(toc.entries.size).to eq(1)
      expect(toc.entries.first.symlink?).to be true
      expect(toc.entries.first.link_target).to eq("target.txt")
    end

    it "parses file with hardlink" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xar>
          <toc>
            <file id="1">
              <name>hardlink</name>
              <type>file</type>
              <link type="hard">original.txt</link>
            </file>
          </toc>
        </xar>
      XML

      doc = REXML::Document.new(xml)
      toc = described_class.from_xml(doc)

      expect(toc.entries.size).to eq(1)
      expect(toc.entries.first.link_target).to eq("original.txt")
    end

    it "parses directory entry" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xar>
          <toc>
            <file id="1">
              <name>mydir</name>
              <type>directory</type>
              <mode>0755</mode>
            </file>
          </toc>
        </xar>
      XML

      doc = REXML::Document.new(xml)
      toc = described_class.from_xml(doc)

      expect(toc.entries.size).to eq(1)
      expect(toc.entries.first.directory?).to be true
      expect(toc.entries.first.mode).to eq(0o755)
    end
  end
end
