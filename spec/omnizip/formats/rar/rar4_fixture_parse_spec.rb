# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/reader"
require "tmpdir"

RSpec.describe "RAR4 real-archive parsing (libarchive fixtures)" do
  def fixture(name)
    File.join(__dir__, "..", "..", "..", "fixtures", "rar",
              "libarchive_reference", "rar4", name)
  end

  it "lists entries of a WinRAR-created archive with directories" do
    path = fixture("test_read_format_rar.rar")
    skip "fixture missing" unless File.exist?(path)

    reader = Omnizip::Formats::Rar::Reader.new(path)
    reader.open

    entries = reader.list_files
    names = entries.map(&:name)
    expect(names).to include("test.txt", "testdir/test.txt", "testdir",
                             "testemptydir")

    testdir = entries.find { |e| e.name == "testdir" }
    expect(testdir).to be_directory
    expect(testdir.size).to eq(0)

    file = entries.find { |e| e.name == "test.txt" }
    expect(file).not_to be_directory
    expect(file.size).to eq(20)
  end

  it "lists a PPMd-compressed archive header" do
    path = fixture("test_read_format_rar_compress_best.rar")
    skip "fixture missing" unless File.exist?(path)

    reader = Omnizip::Formats::Rar::Reader.new(path)
    reader.open

    entries = reader.list_files
    expect(entries).not_to be_empty
    expect(entries.map(&:name)).to include("LibarchiveAddingTest.html")
  end

  it "extracts real WinRAR-compressed entries byte-exactly via unrar " \
     "fallback (native CRC check rejects non-Omnizip streams)",
     skip: !system("which unrar > /dev/null 2>&1") do
    path = fixture("test_read_format_rar_compress_normal.rar")
    skip "fixture missing" unless File.exist?(path)

    reader = Omnizip::Formats::Rar::Reader.new(path)
    reader.open

    Dir.mktmpdir("omnizip_rar4_real") do |out|
      entry = reader.list_files.find { |e| e.name == "LibarchiveAddingTest.html" }
      dest = File.join(out, "file.html")
      reader.extract_entry(entry.name, dest)

      expect(File.size(dest)).to eq(entry.size)
      expect(Zlib.crc32(File.binread(dest))).to eq(entry.crc)
    end
  end
end
