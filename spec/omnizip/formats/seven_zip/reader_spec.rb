# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Omnizip::Formats::SevenZip::Reader do
  let(:fixtures_dir) do
    File.join(__dir__, "../../../fixtures/seven_zip")
  end

  describe "#initialize" do
    it "creates reader with file path" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture)
      expect(reader.file_path).to eq(fixture)
    end
  end

  describe "#open" do
    it "opens and parses .7z archive" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
      expect(reader.header).not_to be_nil
    end

    it "parses LZMA compressed archive" do
      fixture = File.join(fixtures_dir, "simple_lzma.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
    end

    it "parses LZMA2 compressed archive" do
      fixture = File.join(fixtures_dir, "simple_lzma2.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
    end
  end

  describe "#list_files" do
    it "lists files in archive" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture).open

      files = reader.list_files
      expect(files).to be_an(Array)
      expect(files).not_to be_empty
    end
  end
end

RSpec.describe Omnizip::Formats::SevenZip::Reader, "#open" do
  it "is usable without an explicit open (entries parse on demand)" do
    Dir.mktmpdir("omnizip_7z_lazy") do |tmp|
      src = File.join(tmp, "f.txt")
      File.write(src, "lazy seven zip reader")
      archive = File.join(tmp, "a.7z")
      Omnizip::Formats::SevenZip::Writer.new(archive, solid: false)
        .tap { |w| w.add_file(src, "f.txt") }.write

      reader = described_class.new(archive)
      expect(reader.list_files.map(&:name)).to eq(["f.txt"])

      out = File.join(tmp, "out", "f.txt")
      reader.extract_entry("f.txt", out)
      expect(File.read(out)).to eq("lazy seven zip reader")
    end
  end
end
