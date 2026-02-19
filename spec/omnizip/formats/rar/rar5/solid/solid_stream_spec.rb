# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/solid/solid_stream"

RSpec.describe Omnizip::Formats::Rar::Rar5::Solid::SolidStream do
  describe "#initialize" do
    it "creates empty stream" do
      stream = described_class.new
      expect(stream.files).to be_empty
      expect(stream.concatenated_data).to eq("")
      expect(stream.total_size).to eq(0)
      expect(stream.file_count).to eq(0)
      expect(stream).to be_empty
    end
  end

  describe "#add_file" do
    let(:stream) { described_class.new }

    it "adds file with data" do
      stream.add_file("test.txt", "Hello, World!")

      expect(stream.file_count).to eq(1)
      expect(stream.total_size).to eq(13)
      expect(stream).not_to be_empty
    end

    it "tracks file offsets correctly" do
      stream.add_file("file1.txt", "First")
      stream.add_file("file2.txt", "Second")
      stream.add_file("file3.txt", "Third")

      expect(stream.file_at(0)[:offset]).to eq(0)
      expect(stream.file_at(1)[:offset]).to eq(5)
      expect(stream.file_at(2)[:offset]).to eq(11)
    end

    it "stores file metadata" do
      mtime = Time.now
      stat = double("stat")

      stream.add_file("test.txt", "data", mtime: mtime, stat: stat)

      file = stream.file_at(0)
      expect(file[:filename]).to eq("test.txt")
      expect(file[:size]).to eq(4)
      expect(file[:mtime]).to eq(mtime)
      expect(file[:stat]).to eq(stat)
    end

    it "concatenates file data correctly" do
      stream.add_file("a.txt", "AAA")
      stream.add_file("b.txt", "BBB")
      stream.add_file("c.txt", "CCC")

      expect(stream.concatenated_data).to eq("AAABBBCCC")
      expect(stream.total_size).to eq(9)
    end
  end

  describe "#extract_file_data" do
    let(:stream) { described_class.new }

    before do
      stream.add_file("file1.txt", "First file content")
      stream.add_file("file2.txt", "Second file content")
      stream.add_file("file3.txt", "Third file content")
    end

    it "extracts file by index" do
      expect(stream.extract_file_data(0)).to eq("First file content")
      expect(stream.extract_file_data(1)).to eq("Second file content")
      expect(stream.extract_file_data(2)).to eq("Third file content")
    end

    it "returns nil for invalid index" do
      expect(stream.extract_file_data(3)).to be_nil
      expect(stream.extract_file_data(-1)).to be_nil
    end
  end

  describe "#clear" do
    let(:stream) { described_class.new }

    it "resets stream to empty state" do
      stream.add_file("test.txt", "data")
      stream.add_file("test2.txt", "more data")

      stream.clear

      expect(stream.files).to be_empty
      expect(stream.concatenated_data).to eq("")
      expect(stream.total_size).to eq(0)
      expect(stream.file_count).to eq(0)
      expect(stream).to be_empty
    end
  end

  describe "binary data handling" do
    let(:stream) { described_class.new }

    it "handles binary data correctly" do
      binary_data = "\x00\x01\x02\xFF\xFE".b
      stream.add_file("binary.dat", binary_data)

      expect(stream.extract_file_data(0)).to eq(binary_data)
      expect(stream.concatenated_data.encoding).to eq(Encoding::BINARY)
    end

    it "preserves data integrity across multiple files" do
      data1 = "Text\x00Binary".b
      data2 = "\xFF\xFE\xFD".b
      data3 = "More text".b

      stream.add_file("f1", data1)
      stream.add_file("f2", data2)
      stream.add_file("f3", data3)

      expect(stream.extract_file_data(0)).to eq(data1)
      expect(stream.extract_file_data(1)).to eq(data2)
      expect(stream.extract_file_data(2)).to eq(data3)
    end
  end
end
