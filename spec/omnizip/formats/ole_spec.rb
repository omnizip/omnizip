# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/omnizip/formats/ole"

RSpec.describe Omnizip::Formats::Ole do
  let(:fixture_dir) { File.join(File.dirname(__FILE__), "../../fixtures/ole") }
  let(:test_doc) { File.join(fixture_dir, "test.doc") }
  let(:test_word_six) { File.join(fixture_dir, "test_word_6.doc") }
  let(:test_word_ninety_five) { File.join(fixture_dir, "test_word_95.doc") }
  let(:test_word_ninety_seven) { File.join(fixture_dir, "test_word_97.doc") }
  let(:ole_with_dirs) { File.join(fixture_dir, "oleWithDirs.ole") }

  describe ".open" do
    it "opens and yields storage" do
      described_class.open(test_doc) do |ole|
        expect(ole).to be_a(Omnizip::Formats::Ole::Storage)
        expect(ole.root).to be_a(Omnizip::Formats::Ole::Dirent)
      end
    end

    it "returns storage without block" do
      ole = described_class.open(test_doc)
      expect(ole).to be_a(Omnizip::Formats::Ole::Storage)
      ole.close
    end
  end

  describe ".list" do
    it "lists root entries" do
      entries = described_class.list(test_word_six)
      expect(entries).to be_an(Array)
      expect(entries).not_to be_empty
    end
  end

  describe ".info" do
    it "returns root info" do
      info = described_class.info(test_word_six)
      expect(info[:name]).to eq("Root Entry")
      expect(info[:type]).to eq(:root)
    end
  end

  describe ".exist?" do
    it "returns true for existing entry" do
      expect(described_class.exist?(test_word_six, "/")).to be true
    end

    it "returns false for non-existing entry" do
      expect(described_class.exist?(test_word_six, "/NonExistent")).to be false
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Header do
  describe ".parse" do
    let(:valid_header_data) do
      Omnizip::Formats::Ole::Constants::MAGIC +
        ("\x00".b * 16) + # clsid
        [59, 3].pack("v2") + # minor_ver, major_ver
        "\xfe\xff".b + # byte_order
        [9, 6].pack("v2") + # b_shift, s_shift
        ("\x00".b * 6) + # reserved
        [0].pack("V") + # csectdir
        [1].pack("V") + # num_bat
        [0xfffffffe].pack("V") + # dirent_start
        ("\x00".b * 4) + # transacting_signature
        [4096].pack("V") + # threshold
        [0xfffffffe].pack("V") + # sbat_start
        [0].pack("V") + # num_sbat
        [0xfffffffe].pack("V") + # mbat_start
        [0].pack("V") # num_mbat
    end

    it "parses valid header" do
      header = described_class.parse(valid_header_data)
      expect(header.magic).to eq(Omnizip::Formats::Ole::Constants::MAGIC)
      expect(header.major_ver).to eq(3)
      expect(header.minor_ver).to eq(59)
      expect(header.num_bat).to eq(1)
    end

    it "raises error for short data" do
      expect do
        described_class.parse("\x00" * 10)
      end.to raise_error(ArgumentError)
    end

    it "raises error for invalid magic" do
      invalid_data = "\x00" * 76
      expect do
        described_class.parse(invalid_data)
      end.to raise_error(ArgumentError, /magic/i)
    end
  end

  describe ".create" do
    it "creates header with defaults" do
      header = described_class.create
      expect(header.magic).to eq(Omnizip::Formats::Ole::Constants::MAGIC)
      expect(header.major_ver).to eq(3)
      expect(header.big_block_size).to eq(512)
      expect(header.small_block_size).to eq(64)
    end
  end

  describe "#big_block_size" do
    it "returns 512 for default b_shift" do
      header = described_class.create
      expect(header.big_block_size).to eq(512)
    end
  end

  describe "#small_block_size" do
    it "returns 64 for default s_shift" do
      header = described_class.create
      expect(header.small_block_size).to eq(64)
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Storage do
  let(:fixture_dir) { File.join(File.dirname(__FILE__), "../../fixtures/ole") }
  let(:test_word_six) { File.join(fixture_dir, "test_word_6.doc") }

  describe "#load" do
    it "loads Word 6 document" do
      storage = described_class.open(test_word_six)
      expect(storage.header).to be_a(Omnizip::Formats::Ole::Header)
      expect(storage.root).to be_a(Omnizip::Formats::Ole::Dirent)
      expect(storage.root.name).to eq("Root Entry")
      storage.close
    end

    it "loads dirents" do
      storage = described_class.open(test_word_six)
      expect(storage.dirents).to be_an(Array)
      expect(storage.dirents.length).to be > 0
      storage.close
    end
  end

  describe "#list" do
    it "lists root entries" do
      storage = described_class.open(test_word_six)
      entries = storage.list("/")
      expect(entries).to be_an(Array)
      expect(entries).to include("WordDocument")
      storage.close
    end
  end

  describe "#read" do
    it "reads file content" do
      storage = described_class.open(test_word_six)
      content = storage.read("/WordDocument")
      expect(content).to be_a(String)
      expect(content.length).to be > 0
      storage.close
    end

    it "raises error for non-existent path" do
      storage = described_class.open(test_word_six)
      expect { storage.read("/NonExistent") }.to raise_error(Errno::ENOENT)
      storage.close
    end
  end

  describe "#find_dirent" do
    it "finds root dirent" do
      storage = described_class.open(test_word_six)
      dirent = storage.find_dirent("/")
      expect(dirent).to eq(storage.root)
      storage.close
    end

    it "finds child dirent" do
      storage = described_class.open(test_word_six)
      dirent = storage.find_dirent("/WordDocument")
      expect(dirent).to be_a(Omnizip::Formats::Ole::Dirent)
      expect(dirent.name).to eq("WordDocument")
      storage.close
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Dirent do
  describe "#file?" do
    it "returns true for file entries" do
      fixture_dir = File.join(File.dirname(__FILE__), "../../fixtures/ole")
      test_word_six = File.join(fixture_dir, "test_word_6.doc")

      Omnizip::Formats::Ole::Storage.open(test_word_six) do |storage|
        word_doc = storage.find_dirent("/WordDocument")
        expect(word_doc.file?).to be true
      end
    end
  end

  describe "#dir?" do
    it "returns true for directory entries" do
      fixture_dir = File.join(File.dirname(__FILE__), "../../fixtures/ole")
      test_word_six = File.join(fixture_dir, "test_word_6.doc")

      Omnizip::Formats::Ole::Storage.open(test_word_six) do |storage|
        expect(storage.root.dir?).to be true
      end
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Types::Lpwstr do
  describe ".load" do
    it "decodes UTF-16LE string" do
      utf16_data = "t\x00e\x00s\x00t\x00\x00\x00".b
      result = described_class.load(utf16_data)
      expect(result).to eq("test")
    end

    it "handles empty string" do
      result = described_class.load("")
      expect(result).to eq("")
    end
  end

  describe ".dump" do
    it "encodes to UTF-16LE" do
      result = described_class.dump("test")
      expect(result).to eq("t\x00e\x00s\x00t\x00\x00\x00".b)
    end

    it "handles empty string" do
      result = described_class.dump("")
      expect(result).to eq("\x00\x00".b)
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Types::Lpstr do
  describe ".load" do
    it "strips null terminator" do
      result = described_class.load("test\x00")
      expect(result).to eq("test")
    end
  end

  describe ".dump" do
    it "returns string as-is" do
      result = described_class.dump("test")
      expect(result).to eq("test")
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Types::FileTime do
  describe ".load" do
    it "parses valid FILETIME" do
      # 2007-01-01 00:00:00 UTC
      data = "\x00\x00\xb0\xc7\x37\x2d\xc7\x01".b
      result = described_class.load(data)
      expect(result).to be_a(described_class)
      expect(result.to_s).to include("2007-01-01")
    end

    it "returns nil for zero time" do
      result = described_class.load("\x00" * 8)
      expect(result).to be_nil
    end
  end

  describe ".dump" do
    it "dumps to 8-byte binary" do
      time = DateTime.new(2007, 1, 1)
      result = described_class.dump(time)
      expect(result.bytesize).to eq(8)
    end

    it "returns 8 null bytes for nil" do
      result = described_class.dump(nil)
      expect(result).to eq("\x00" * 8)
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Types::Clsid do
  describe ".parse" do
    it "parses GUID string" do
      guid = described_class.parse("{00020329-0880-4007-c001-123456789046}")
      expect(guid.bytesize).to eq(16)
    end

    it "raises error for invalid format" do
      expect { described_class.parse("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#format" do
    it "formats to standard GUID string" do
      data = "\x29\x03\x02\x00\x80\x08\x07\x40\xc0\x01\x12\x34\x56\x78\x90\x46".b
      guid = described_class.load(data)
      expect(guid.format).to eq("00020329-0880-4007-c001-123456789046")
    end
  end
end

RSpec.describe Omnizip::Formats::Ole::Types::Variant do
  describe ".load" do
    it "loads VT_LPWSTR" do
      data = "t\x00e\x00s\x00t\x00\x00\x00".b
      result = described_class.load(described_class::VT_LPWSTR, data)
      expect(result).to eq("test")
    end
  end

  describe ".dump" do
    it "dumps VT_LPWSTR" do
      result = described_class.dump(described_class::VT_LPWSTR, "test")
      expect(result).to include("t\x00".b)
    end
  end
end
