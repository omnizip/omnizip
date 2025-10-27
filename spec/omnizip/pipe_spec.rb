# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

RSpec.describe Omnizip::Pipe do
  describe ".compress" do
    let(:input_data) { "Hello, World! This is test data for compression." }
    let(:input_io) { StringIO.new(input_data) }
    let(:output_io) { StringIO.new("".b) }

    it "compresses from IO to IO" do
      bytes = described_class.compress(input_io, output_io, format: :zip)

      expect(bytes).to be > 0
      expect(output_io.string).not_to be_empty
      expect(output_io.string[0..1]).to eq("PK") # ZIP magic bytes
    end

    it "compresses with custom entry name" do
      described_class.compress(
        input_io,
        output_io,
        format: :zip,
        entry_name: "custom.txt"
      )

      output_io.rewind
      extracted = Omnizip::Buffer.extract_to_memory(output_io.string)
      expect(extracted.keys).to include("custom.txt")
    end

    it "compresses with compression level" do
      described_class.compress(
        input_io,
        output_io,
        format: :zip,
        level: 9
      )

      expect(output_io.string).not_to be_empty
    end

    it "handles large data streams" do
      large_data = "A" * 1_000_000 # 1MB
      large_input = StringIO.new(large_data)

      bytes = described_class.compress(large_input, output_io, format: :zip)

      expect(bytes).to be > 0
      output_io.rewind
      extracted = Omnizip::Buffer.extract_to_memory(output_io.string)
      expect(extracted.values.first.size).to eq(large_data.size)
    end

    it "raises error for unsupported format" do
      expect {
        described_class.compress(input_io, output_io, format: :invalid)
      }.to raise_error(ArgumentError, /Unsupported format/)
    end

    context "with real files" do
      let(:input_file) { Tempfile.new(["input", ".txt"]) }
      let(:output_file) { Tempfile.new(["output", ".zip"]) }

      before do
        input_file.write(input_data)
        input_file.rewind
      end

      after do
        input_file.close
        input_file.unlink
        output_file.close
        output_file.unlink
      end

      it "compresses file to file" do
        File.open(input_file.path, "rb") do |input|
          File.open(output_file.path, "wb") do |output|
            described_class.compress(input, output, format: :zip)
          end
        end

        expect(File.size(output_file.path)).to be > 0
        extracted = Omnizip::Buffer.extract_to_memory(File.binread(output_file.path))
        expect(extracted.values.first).to eq(input_data)
      end
    end
  end

  describe ".decompress" do
    let(:test_data) { { "file1.txt" => "Content 1", "file2.txt" => "Content 2" } }
    let(:archive_io) do
      Omnizip::Buffer.create_from_hash(test_data, :zip)
    end

    context "to directory" do
      let(:output_dir) { Dir.mktmpdir }

      after do
        FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
      end

      it "extracts to directory" do
        archive_io.rewind
        result = described_class.decompress(archive_io, output_dir: output_dir)

        expect(result).to be_a(Hash)
        expect(result.keys).to match_array(test_data.keys)
        expect(File.read(File.join(output_dir, "file1.txt"))).to eq("Content 1")
        expect(File.read(File.join(output_dir, "file2.txt"))).to eq("Content 2")
      end

      it "creates output directory if it doesn't exist" do
        new_dir = File.join(output_dir, "new_subdir")
        archive_io.rewind

        described_class.decompress(archive_io, output_dir: new_dir)

        expect(Dir.exist?(new_dir)).to be true
        expect(File.exist?(File.join(new_dir, "file1.txt"))).to be true
      end
    end

    context "to stream" do
      let(:output_stream) { StringIO.new("".b) }

      it "extracts first file to stream" do
        archive_io.rewind
        bytes = described_class.decompress(archive_io, output: output_stream)

        expect(bytes).to be > 0
        expect(output_stream.string).to eq("Content 1")
      end

      it "handles single-file archives" do
        single_file = Omnizip::Buffer.create(:zip) do |archive|
          archive.add("single.txt", "Single file content")
        end
        single_file.rewind

        bytes = described_class.decompress(single_file, output: output_stream)

        expect(bytes).to eq("Single file content".bytesize)
        expect(output_stream.string).to eq("Single file content")
      end
    end

    it "raises error when neither output_dir nor output specified" do
      expect {
        described_class.decompress(archive_io)
      }.to raise_error(ArgumentError, /output_dir or output must be specified/)
    end
  end

  describe ".pipe_mode?" do
    it "detects pipe mode based on TTY status" do
      # The actual result depends on how tests are run
      # Just verify it returns a boolean
      result = described_class.pipe_mode?
      expect([true, false]).to include(result)
    end
  end

  describe ".stdin?" do
    it "detects stdin from '-'" do
      expect(described_class.stdin?("-")).to be true
    end

    it "detects stdin from $stdin" do
      expect(described_class.stdin?($stdin)).to be true
    end

    it "returns false for file paths" do
      expect(described_class.stdin?("file.txt")).to be false
    end
  end

  describe ".stdout?" do
    it "detects stdout from '-'" do
      expect(described_class.stdout?("-")).to be true
    end

    it "detects stdout from $stdout" do
      expect(described_class.stdout?($stdout)).to be true
    end

    it "returns false for file paths" do
      expect(described_class.stdout?("file.txt")).to be false
    end
  end

  describe "StreamCompressor" do
    let(:input_data) { "Test data for stream compression" }
    let(:input_io) { StringIO.new(input_data) }
    let(:output_io) { StringIO.new("".b) }

    describe "#compress" do
      it "compresses to ZIP format" do
        compressor = Omnizip::Pipe::StreamCompressor.new(
          input_io,
          output_io,
          :zip
        )

        bytes = compressor.compress

        expect(bytes).to be > 0
        expect(compressor.bytes_written).to eq(bytes)
        expect(output_io.string[0..1]).to eq("PK")
      end

      it "handles custom chunk sizes" do
        compressor = Omnizip::Pipe::StreamCompressor.new(
          input_io,
          output_io,
          :zip,
          chunk_size: 10
        )

        compressor.compress

        expect(output_io.string).not_to be_empty
      end

      it "calls progress callback" do
        progress_calls = []
        compressor = Omnizip::Pipe::StreamCompressor.new(
          input_io,
          output_io,
          :zip,
          progress: ->(read, written) { progress_calls << [read, written] }
        )

        compressor.compress

        expect(progress_calls).not_to be_empty
      end

      it "raises error for 7z format" do
        compressor = Omnizip::Pipe::StreamCompressor.new(
          input_io,
          output_io,
          :seven_zip
        )

        expect {
          compressor.compress
        }.to raise_error(NotImplementedError, /7z pipe compression/)
      end
    end
  end

  describe "StreamDecompressor" do
    let(:test_files) { { "test.txt" => "Test content" } }
    let(:archive_data) do
      buffer = Omnizip::Buffer.create_from_hash(test_files, :zip)
      buffer.string
    end
    let(:archive_io) { StringIO.new(archive_data) }

    describe "#decompress" do
      context "to stream" do
        let(:output_stream) { StringIO.new("".b) }

        it "decompresses to output stream" do
          decompressor = Omnizip::Pipe::StreamDecompressor.new(
            archive_io,
            output: output_stream
          )

          bytes = decompressor.decompress

          expect(bytes).to eq("Test content".bytesize)
          expect(output_stream.string).to eq("Test content")
        end

        it "handles custom chunk sizes" do
          decompressor = Omnizip::Pipe::StreamDecompressor.new(
            archive_io,
            output: output_stream,
            chunk_size: 5
          )

          decompressor.decompress

          expect(output_stream.string).to eq("Test content")
        end
      end

      context "to directory" do
        let(:output_dir) { Dir.mktmpdir }

        after do
          FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
        end

        it "extracts to directory" do
          decompressor = Omnizip::Pipe::StreamDecompressor.new(
            archive_io,
            output_dir: output_dir
          )

          result = decompressor.decompress

          expect(result).to be_a(Hash)
          expect(result["test.txt"]).to eq("Test content".bytesize)
          expect(File.read(File.join(output_dir, "test.txt"))).to eq("Test content")
        end

        it "preserves directory structure" do
          nested_files = {
            "dir1/file1.txt" => "Content 1",
            "dir2/file2.txt" => "Content 2"
          }
          nested_archive = StringIO.new(
            Omnizip::Buffer.create_from_hash(nested_files, :zip).string
          )

          decompressor = Omnizip::Pipe::StreamDecompressor.new(
            nested_archive,
            output_dir: output_dir,
            preserve_paths: true
          )

          decompressor.decompress

          expect(File.exist?(File.join(output_dir, "dir1", "file1.txt"))).to be true
          expect(File.exist?(File.join(output_dir, "dir2", "file2.txt"))).to be true
        end

        it "flattens structure when preserve_paths is false" do
          nested_files = { "dir/file.txt" => "Content" }
          nested_archive = StringIO.new(
            Omnizip::Buffer.create_from_hash(nested_files, :zip).string
          )

          decompressor = Omnizip::Pipe::StreamDecompressor.new(
            nested_archive,
            output_dir: output_dir,
            preserve_paths: false
          )

          decompressor.decompress

          expect(File.exist?(File.join(output_dir, "file.txt"))).to be true
          expect(File.exist?(File.join(output_dir, "dir"))).to be false
        end
      end
    end
  end

  describe "integration scenarios" do
    it "round-trips data through pipe compression and decompression" do
      original_data = "This is the original data that will be compressed and decompressed"

      # Compress
      compressed_io = StringIO.new("".b)
      Omnizip::Pipe.compress(
        StringIO.new(original_data),
        compressed_io,
        format: :zip,
        entry_name: "data.txt"
      )

      # Decompress
      compressed_io.rewind
      decompressed_io = StringIO.new("".b)
      Omnizip::Pipe.decompress(compressed_io, output: decompressed_io)

      expect(decompressed_io.string).to eq(original_data)
    end

    it "handles empty input gracefully" do
      empty_input = StringIO.new("")
      output = StringIO.new("".b)

      Omnizip::Pipe.compress(empty_input, output, format: :zip)

      expect(output.string).not_to be_empty
      output.rewind
      extracted = Omnizip::Buffer.extract_to_memory(output.string)
      expect(extracted.values.first).to eq("")
    end

    it "processes large streams efficiently" do
      # Create 5MB of data
      large_data = "X" * (5 * 1024 * 1024)
      input = StringIO.new(large_data)
      output = StringIO.new("".b)

      # Compress with small chunk size to test chunking
      Omnizip::Pipe.compress(
        input,
        output,
        format: :zip,
        chunk_size: 64 * 1024
      )

      # Verify compression worked
      expect(output.string.size).to be < large_data.size
      expect(output.string[0..1]).to eq("PK")

      # Decompress and verify
      output.rewind
      decompressed = StringIO.new("".b)
      Omnizip::Pipe.decompress(output, output: decompressed)

      expect(decompressed.string.size).to eq(large_data.size)
    end
  end
end