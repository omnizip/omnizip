# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/omnizip/zip/output_stream"
require_relative "../../../lib/omnizip/zip/input_stream"

RSpec.describe "Omnizip::Zip Stream Classes" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:zip_path) { File.join(temp_dir, "stream_test.zip") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe Omnizip::Zip::OutputStream do
    describe ".open" do
      it "creates new archive with block" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("test.txt")
          zos.write("Hello, World!")
        end

        expect(File.exist?(zip_path)).to be true
      end

      it "returns stream without block" do
        stream = described_class.open(zip_path)
        expect(stream).to be_a(described_class)
        stream.put_next_entry("test.txt")
        stream.write("content")
        stream.close
      end
    end

    describe "#put_next_entry" do
      it "starts new entry" do
        described_class.open(zip_path) do |zos|
          result = zos.put_next_entry("file.txt")
          expect(result).to eq(zos)
        end
      end

      it "accepts time parameter" do
        time = Time.new(2020, 1, 1, 12, 0, 0)

        described_class.open(zip_path) do |zos|
          zos.put_next_entry("file.txt", time: time)
          zos.write("content")
        end

        # Verify by reading back
        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          entry = zis.get_next_entry
          expect(entry.time.year).to eq(2020)
          expect(entry.time.month).to eq(1)
          expect(entry.time.day).to eq(1)
        end
      end

      it "accepts compression parameter" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("stored.txt", compression: :store)
          zos.write("content")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          entry = zis.get_next_entry
          expect(entry.compression_method).to eq(0) # STORE
        end
      end

      it "handles directory entries" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("dir/")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          entry = zis.get_next_entry
          expect(entry.directory?).to be true
        end
      end
    end

    describe "#write" do
      it "writes data to current entry" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("test.txt")
          result = zos.write("Hello")
          expect(result).to eq(zos)
        end
      end

      it "raises error without entry" do
        stream = described_class.open(zip_path)
        expect {
          stream.write("data")
        }.to raise_error(/No entry started/)
        stream.close
      end

      it "handles binary data" do
        binary_data = "\x00\x01\x02\xFF".b

        described_class.open(zip_path) do |zos|
          zos.put_next_entry("binary.dat")
          zos.write(binary_data)
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          zis.get_next_entry
          content = zis.read
          expect(content).to eq(binary_data)
        end
      end
    end

    describe "#<<" do
      it "is alias for write" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("test.txt")
          expect(zos.method(:<<)).to eq(zos.method(:write))
        end
      end
    end

    describe "#print" do
      it "prints data without newline" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("test.txt")
          zos.print("Hello", " ", "World")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          zis.get_next_entry
          expect(zis.read).to eq("Hello World")
        end
      end
    end

    describe "#puts" do
      it "prints data with newlines" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("test.txt")
          zos.puts("Line 1", "Line 2")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          zis.get_next_entry
          expect(zis.read).to eq("Line 1\nLine 2\n")
        end
      end
    end

    describe "#close_entry" do
      it "finalizes current entry" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("file1.txt")
          zos.write("content1")
          zos.close_entry

          zos.put_next_entry("file2.txt")
          zos.write("content2")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          entry1 = zis.get_next_entry
          expect(entry1.name).to eq("file1.txt")

          entry2 = zis.get_next_entry
          expect(entry2.name).to eq("file2.txt")
        end
      end
    end

    describe "#comment" do
      it "sets archive comment" do
        described_class.open(zip_path) do |zos|
          zos.comment = "Test archive"
          zos.put_next_entry("test.txt")
          zos.write("content")
        end

        expect(File.exist?(zip_path)).to be true
      end
    end

    describe "#close" do
      it "finalizes and closes stream" do
        stream = described_class.open(zip_path)
        stream.put_next_entry("test.txt")
        stream.write("content")
        stream.close

        expect(stream.closed?).to be true
        expect(File.exist?(zip_path)).to be true
      end

      it "handles multiple close calls" do
        stream = described_class.open(zip_path)
        stream.put_next_entry("test.txt")
        stream.write("content")
        stream.close

        expect { stream.close }.not_to raise_error
      end
    end

    describe "multiple entries" do
      it "writes multiple entries correctly" do
        described_class.open(zip_path) do |zos|
          zos.put_next_entry("file1.txt")
          zos.write("Content 1")

          zos.put_next_entry("file2.txt")
          zos.write("Content 2")

          zos.put_next_entry("file3.txt")
          zos.write("Content 3")
        end

        Omnizip::Zip::InputStream.open(zip_path) do |zis|
          entries = []
          while entry = zis.get_next_entry
            entries << { name: entry.name, content: zis.read }
          end

          expect(entries.size).to eq(3)
          expect(entries[0][:name]).to eq("file1.txt")
          expect(entries[0][:content]).to eq("Content 1")
          expect(entries[1][:name]).to eq("file2.txt")
          expect(entries[1][:content]).to eq("Content 2")
          expect(entries[2][:name]).to eq("file3.txt")
          expect(entries[2][:content]).to eq("Content 3")
        end
      end
    end
  end

  describe Omnizip::Zip::InputStream do
    before do
      # Create test archive
      Omnizip::Zip::OutputStream.open(zip_path) do |zos|
        zos.put_next_entry("file1.txt")
        zos.write("Content of file 1")

        zos.put_next_entry("file2.txt")
        zos.write("Content of file 2")

        zos.put_next_entry("dir/")

        zos.put_next_entry("dir/file3.txt")
        zos.write("Content of file 3")
      end
    end

    describe ".open" do
      it "opens archive with block" do
        described_class.open(zip_path) do |zis|
          expect(zis).to be_a(described_class)
        end
      end

      it "returns stream without block" do
        stream = described_class.open(zip_path)
        expect(stream).to be_a(described_class)
        stream.close
      end
    end

    describe "#get_next_entry" do
      it "returns next entry" do
        described_class.open(zip_path) do |zis|
          entry = zis.get_next_entry
          expect(entry).to be_a(Omnizip::Zip::Entry)
          expect(entry.name).to eq("file1.txt")
        end
      end

      it "returns nil at end" do
        described_class.open(zip_path) do |zis|
          4.times { zis.get_next_entry }
          expect(zis.get_next_entry).to be_nil
        end
      end

      it "iterates through all entries" do
        described_class.open(zip_path) do |zis|
          names = []
          while entry = zis.get_next_entry
            names << entry.name
          end
          expect(names).to eq(["file1.txt", "file2.txt", "dir/", "dir/file3.txt"])
        end
      end
    end

    describe "#read" do
      it "reads current entry content" do
        described_class.open(zip_path) do |zis|
          zis.get_next_entry
          content = zis.read
          expect(content).to eq("Content of file 1")
        end
      end

      it "reads partial content with size" do
        described_class.open(zip_path) do |zis|
          zis.get_next_entry
          partial = zis.read(7)
          expect(partial).to eq("Content")
        end
      end

      it "returns nil without current entry" do
        described_class.open(zip_path) do |zis|
          expect(zis.read).to be_nil
        end
      end

      it "can read multiple times from same entry" do
        described_class.open(zip_path) do |zis|
          zis.get_next_entry
          part1 = zis.read(7)
          part2 = zis.read(4)
          expect(part1 + part2).to eq("Content of ")
        end
      end
    end

    describe "#rewind" do
      it "resets to beginning" do
        described_class.open(zip_path) do |zis|
          zis.get_next_entry
          zis.get_next_entry

          zis.rewind

          entry = zis.get_next_entry
          expect(entry.name).to eq("file1.txt")
        end
      end
    end

    describe "#eof?" do
      it "returns false when entries remain" do
        described_class.open(zip_path) do |zis|
          expect(zis.eof?).to be false
        end
      end

      it "returns true at end" do
        described_class.open(zip_path) do |zis|
          4.times { zis.get_next_entry }
          expect(zis.eof?).to be true
        end
      end
    end

    describe "#eof" do
      it "is alias for eof?" do
        described_class.open(zip_path) do |zis|
          expect(zis.method(:eof)).to eq(zis.method(:eof?))
        end
      end
    end

    describe "#close" do
      it "closes the stream" do
        stream = described_class.open(zip_path)
        stream.close
        expect(stream.closed?).to be true
      end
    end

    describe "integration" do
      it "reads all entries and content" do
        entries = []

        described_class.open(zip_path) do |zis|
          while entry = zis.get_next_entry
            content = entry.directory? ? nil : zis.read
            entries << { name: entry.name, content: content, directory: entry.directory? }
          end
        end

        expect(entries.size).to eq(4)
        expect(entries[0][:name]).to eq("file1.txt")
        expect(entries[0][:content]).to eq("Content of file 1")
        expect(entries[1][:name]).to eq("file2.txt")
        expect(entries[1][:content]).to eq("Content of file 2")
        expect(entries[2][:name]).to eq("dir/")
        expect(entries[2][:directory]).to be true
        expect(entries[3][:name]).to eq("dir/file3.txt")
        expect(entries[3][:content]).to eq("Content of file 3")
      end
    end
  end
end