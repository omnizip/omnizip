# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require "digest"

RSpec.describe Omnizip::Formats::Xar do
  let(:fixtures_dir) { File.expand_path("../../../fixtures/xar", __dir__) }

  describe ".create" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }

    after do
      temp_file.close
      temp_file.unlink
    end

    it "creates an empty XAR archive" do
      described_class.create(output_path)

      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 28 # At least header size
    end

    it "creates a XAR archive with a single file" do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "hellohellohello\n", mode: 0o644)
      end

      expect(File.exist?(output_path)).to be true

      # Read back and verify
      entries = described_class.list(output_path)
      expect(entries.size).to eq(1)
      expect(entries.first.name).to eq("f1")
    end

    it "creates a XAR archive with multiple files" do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "onetwothree\n")
        xar.add_data("f2", "fourfivesix\n")
      end

      entries = described_class.list(output_path)
      expect(entries.size).to eq(2)
      expect(entries.map(&:name)).to contain_exactly("f1", "f2")
    end

    it "creates a XAR archive with a directory" do
      described_class.create(output_path) do |xar|
        xar.add_data("dir1/file.txt", "test content")
      end

      entries = described_class.list(output_path)
      expect(entries.size).to eq(1)
      expect(entries.first.name).to eq("dir1/file.txt")
    end

    it "creates a XAR archive with a symlink" do
      described_class.create(output_path) do |xar|
        entry = Omnizip::Formats::Xar::Entry.new("symlink", type: "symlink")
        entry.link_type = "symbolic"
        entry.link_target = "f1"
        entry.mode = 0o755
        xar.add_entry(entry)
      end

      entries = described_class.list(output_path)
      expect(entries.size).to eq(1)
      expect(entries.first.symlink?).to be true
      expect(entries.first.link_target).to eq("f1")
    end

    it "creates a XAR archive with gzip compression" do
      described_class.create(output_path, compression: "gzip") do |xar|
        xar.add_data("f1", "hellohellohello\n" * 100)
      end

      expect(File.exist?(output_path)).to be true
      entries = described_class.list(output_path)
      expect(entries.size).to eq(1)
    end

    it "creates a XAR archive with no compression" do
      described_class.create(output_path, compression: "none") do |xar|
        xar.add_data("f1", "hellohellohello\n")
      end

      expect(File.exist?(output_path)).to be true
      entries = described_class.list(output_path)
      expect(entries.size).to eq(1)
    end

    it "creates a XAR archive with SHA1 checksum" do
      described_class.create(output_path, toc_checksum: "sha1") do |xar|
        xar.add_data("f1", "hellohellohello\n")
      end

      expect(File.exist?(output_path)).to be true
    end

    it "creates a XAR archive with MD5 checksum" do
      described_class.create(output_path, toc_checksum: "md5") do |xar|
        xar.add_data("f1", "hellohellohello\n")
      end

      expect(File.exist?(output_path)).to be true
    end

    it "creates a XAR archive with no checksum" do
      described_class.create(output_path, toc_checksum: "none") do |xar|
        xar.add_data("f1", "hellohellohello\n")
      end

      expect(File.exist?(output_path)).to be true
    end
  end

  describe ".open" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }

    after do
      temp_file.close
      temp_file.unlink
    end

    before do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "hellohellohello\n", mode: 0o644)
      end
    end

    it "opens and reads a XAR archive" do
      reader = described_class.open(output_path)
      expect(reader).to be_a(Omnizip::Formats::Xar::Reader)
      expect(reader.entries.size).to eq(1)
      reader.close
    end

    it "yields a reader to a block" do
      described_class.open(output_path) do |reader|
        expect(reader.entries.size).to eq(1)
      end
    end
  end

  describe ".list" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }

    after do
      temp_file.close
      temp_file.unlink
    end

    before do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "hellohellohello\n")
        xar.add_data("f2", "worldworldworld\n")
      end
    end

    it "lists all entries in the archive" do
      entries = described_class.list(output_path)
      expect(entries.size).to eq(2)
      expect(entries.map(&:name)).to contain_exactly("f1", "f2")
    end
  end

  describe ".extract" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }
    let(:extract_dir) { Dir.mktmpdir("xar_extract") }

    after do
      temp_file.close
      temp_file.unlink
      FileUtils.rm_rf(extract_dir)
    end

    before do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "hellohellohello\n")
        xar.add_data("dir/f2", "worldworldworld\n")
      end
    end

    it "extracts all files from the archive" do
      described_class.extract(output_path, extract_dir)

      expect(File.exist?(File.join(extract_dir, "f1"))).to be true
      expect(File.exist?(File.join(extract_dir, "dir/f2"))).to be true
      expect(File.read(File.join(extract_dir, "f1"))).to eq("hellohellohello\n")
    end
  end

  describe ".info" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }

    after do
      temp_file.close
      temp_file.unlink
    end

    before do
      described_class.create(output_path) do |xar|
        xar.add_data("f1", "hellohellohello\n")
      end
    end

    it "returns archive information" do
      info = described_class.info(output_path)

      expect(info[:entry_count]).to eq(1)
      expect(info[:file_count]).to eq(1)
      expect(info[:header][:version]).to eq(1)
    end
  end

  describe "round-trip" do
    let(:temp_file) { Tempfile.new(["test", ".xar"]) }
    let(:output_path) { temp_file.path }
    let(:extract_dir) { Dir.mktmpdir("xar_extract") }

    after do
      temp_file.close
      temp_file.unlink
      FileUtils.rm_rf(extract_dir)
    end

    it "creates and reads back a simple file" do
      content = "This is test content\n" * 10

      described_class.create(output_path) do |xar|
        xar.add_data("test.txt", content, mode: 0o644)
      end

      described_class.extract(output_path, extract_dir)

      extracted_path = File.join(extract_dir, "test.txt")
      expect(File.exist?(extracted_path)).to be true
      expect(File.read(extracted_path)).to eq(content)
    end

    it "preserves file metadata" do
      mtime = Time.new(2020, 1, 1, 12, 0, 0)

      described_class.create(output_path) do |xar|
        xar.add_data("test.txt", "content", mode: 0o755, mtime: mtime)
      end

      described_class.extract(output_path, extract_dir)

      extracted_path = File.join(extract_dir, "test.txt")
      expect(File.stat(extracted_path).mode & 0o777).to eq(0o755)
    end
  end
end
