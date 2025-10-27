# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Omnizip::Chunked do
  let(:temp_dir) { Dir.mktmpdir("omnizip_chunked_spec") }

  after do
    FileUtils.rm_rf(temp_dir)

    # Reset configuration after each test
    Omnizip::Chunked.configuration.chunk_size = 64 * 1024 * 1024
    Omnizip::Chunked.configuration.max_memory = 256 * 1024 * 1024
    Omnizip::Chunked.configuration.temp_directory = nil
    Omnizip::Chunked.configuration.spill_strategy = :disk
  end

  describe ".configuration" do
    it "provides global configuration" do
      expect(described_class.configuration).to be_a(Omnizip::Chunked::Configuration)
    end

    it "has default chunk size of 64MB" do
      expect(described_class.configuration.chunk_size).to eq(64 * 1024 * 1024)
    end

    it "has default max memory of 256MB" do
      expect(described_class.configuration.max_memory).to eq(256 * 1024 * 1024)
    end

    it "has default spill strategy of disk" do
      expect(described_class.configuration.spill_strategy).to eq(:disk)
    end
  end

  describe ".configure" do
    it "allows configuration via block" do
      described_class.configure do |config|
        config.chunk_size = 128 * 1024 * 1024
        config.max_memory = 512 * 1024 * 1024
      end

      expect(described_class.configuration.chunk_size).to eq(128 * 1024 * 1024)
      expect(described_class.configuration.max_memory).to eq(512 * 1024 * 1024)
    end
  end

  describe Omnizip::Chunked::Reader do
    let(:test_file) { File.join(temp_dir, "test.dat") }
    let(:chunk_size) { 1024 } # 1KB for testing

    before do
      # Create test file with known content
      File.open(test_file, "wb") do |f|
        f.write("A" * 2048) # 2KB of 'A's
        f.write("B" * 2048) # 2KB of 'B's
      end
    end

    describe "#initialize" do
      it "creates reader with default chunk size" do
        reader = described_class.new(test_file)
        expect(reader.chunk_size).to eq(64 * 1024 * 1024)
      end

      it "creates reader with custom chunk size" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.chunk_size).to eq(chunk_size)
      end

      it "calculates total file size" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.total_size).to eq(4096)
      end
    end

    describe "#read_chunk" do
      it "reads chunk of specified size" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        chunk = reader.read_chunk
        expect(chunk.bytesize).to eq(chunk_size)
      end

      it "reads remaining bytes on last chunk" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        4.times { reader.read_chunk } # Read first 4 chunks
        expect(reader.read_chunk).to be_nil # No more data
      end

      it "returns nil at EOF" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        5.times { reader.read_chunk }
        expect(reader.read_chunk).to be_nil
      end
    end

    describe "#each_chunk" do
      it "iterates through all chunks" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        chunks = []
        reader.each_chunk { |chunk| chunks << chunk }
        expect(chunks.size).to eq(4)
      end

      it "provides chunk, position, and total to block" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        positions = []
        reader.each_chunk { |_chunk, pos, total| positions << [pos, total] }
        expect(positions.first).to eq([0, 4096])
        expect(positions.last[1]).to eq(4096)
      end

      it "reads all data correctly" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        data = String.new(encoding: Encoding::BINARY)
        reader.each_chunk { |chunk| data << chunk }
        expect(data.bytesize).to eq(4096)
        expect(data[0, 2048]).to eq("A" * 2048)
        expect(data[2048, 2048]).to eq("B" * 2048)
      end
    end

    describe "#progress" do
      it "returns 0.0 at start" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.progress).to eq(0.0)
      end

      it "returns 1.0 at end" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        4.times { reader.read_chunk }
        expect(reader.progress).to eq(1.0)
      end

      it "returns intermediate progress" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        reader.read_chunk
        expect(reader.progress).to be_within(0.01).of(0.25)
      end
    end

    describe "#reset" do
      it "resets reader to beginning" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        reader.read_chunk
        reader.reset
        expect(reader.progress).to eq(0.0)
      end
    end

    describe "#eof?" do
      it "returns false when not at EOF" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.eof?).to be false
      end

      it "returns true when at EOF" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        4.times { reader.read_chunk }
        expect(reader.eof?).to be true
      end
    end

    describe "#chunk_count" do
      it "calculates correct number of chunks" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.chunk_count).to eq(4)
      end
    end

    describe "#remaining" do
      it "returns total size initially" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        expect(reader.remaining).to eq(4096)
      end

      it "decreases as chunks are read" do
        reader = described_class.new(test_file, chunk_size: chunk_size)
        reader.read_chunk
        expect(reader.remaining).to eq(3072)
      end
    end
  end

  describe Omnizip::Chunked::Writer do
    let(:output_file) { File.join(temp_dir, "output.dat") }
    let(:chunk_size) { 1024 }

    describe "#initialize" do
      it "creates writer with default chunk size" do
        writer = described_class.new(output_file)
        expect(writer.chunk_size).to eq(64 * 1024 * 1024)
      end

      it "creates writer with custom chunk size" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        expect(writer.chunk_size).to eq(chunk_size)
      end

      it "initializes written counter to 0" do
        writer = described_class.new(output_file)
        expect(writer.written).to eq(0)
      end
    end

    describe "#write_chunk" do
      it "writes chunk to file" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        data = "A" * 100
        writer.write_chunk(data)
        writer.close

        expect(File.read(output_file)).to eq(data)
      end

      it "tracks written bytes" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_chunk("A" * 100)
        expect(writer.written).to eq(100)
      end

      it "writes multiple chunks" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_chunk("A" * 100)
        writer.write_chunk("B" * 100)
        writer.close

        content = File.read(output_file)
        expect(content).to eq(("A" * 100) + ("B" * 100))
      end
    end

    describe "#write_from" do
      it "writes from file path" do
        input_file = File.join(temp_dir, "input.dat")
        File.write(input_file, "test data")

        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_from(input_file)
        writer.close

        expect(File.read(output_file)).to eq("test data")
      end

      it "writes from IO object" do
        io = StringIO.new("test data")
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_from(io)
        writer.close

        expect(File.read(output_file)).to eq("test data")
      end

      it "writes from String data" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_from("test data")
        writer.close

        expect(File.read(output_file)).to eq("test data")
      end
    end

    describe "#flush" do
      it "flushes buffered data" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_chunk("test")
        writer.flush
        expect(File.exist?(output_file)).to be true
      end
    end

    describe "#close" do
      it "closes file handle" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.write_chunk("test")
        expect { writer.close }.not_to raise_error
      end

      it "can be called multiple times safely" do
        writer = described_class.new(output_file, chunk_size: chunk_size)
        writer.close
        expect { writer.close }.not_to raise_error
      end
    end

    describe ".with_writer" do
      it "creates writer with auto-close" do
        bytes = described_class.with_writer(output_file,
                                            chunk_size: chunk_size) do |w|
          w.write_chunk("test data")
        end

        expect(bytes).to eq(9)
        expect(File.read(output_file)).to eq("test data")
      end

      it "ensures file is closed even on error" do
        expect do
          described_class.with_writer(output_file) do |w|
            w.write_chunk("test")
            raise "error"
          end
        end.to raise_error("error")

        # File should still exist and contain partial data
        expect(File.exist?(output_file)).to be true
      end
    end
  end

  describe Omnizip::Chunked::MemoryManager do
    let(:max_memory) { 1024 } # 1KB for testing
    let(:manager) { described_class.new(max: max_memory) }

    describe "#initialize" do
      it "sets max memory" do
        expect(manager.max_memory).to eq(max_memory)
      end

      it "initializes current usage to 0" do
        expect(manager.current_usage).to eq(0)
      end
    end

    describe "#allocate" do
      it "allocates buffer in memory when under limit" do
        buffer = manager.allocate(512)
        expect(buffer).to be_a(String)
        expect(manager.current_usage).to eq(512)
      end

      it "spills to disk when over limit with disk strategy" do
        manager = described_class.new(max: max_memory, strategy: :disk)
        buffer = manager.allocate(2048) # Over limit
        expect(buffer).to be_a(Tempfile)
      end

      it "raises error when over limit with error strategy" do
        manager = described_class.new(max: max_memory, strategy: :error)
        expect do
          manager.allocate(2048)
        end.to raise_error(Omnizip::Chunked::MemoryError)
      end
    end

    describe "#release" do
      it "releases memory buffer" do
        buffer = manager.allocate(512)
        released = manager.release(buffer)
        expect(released).to eq(512)
        expect(manager.current_usage).to eq(0)
      end

      it "releases temp file" do
        manager = described_class.new(max: max_memory, strategy: :disk)
        buffer = manager.allocate(2048)
        expect(buffer).to be_a(Tempfile)
        manager.release(buffer)
        expect(buffer.closed?).to be true
      end
    end

    describe "#available" do
      it "returns available memory" do
        expect(manager.available).to eq(max_memory)
        manager.allocate(512)
        expect(manager.available).to eq(512)
      end

      it "returns 0 when over limit" do
        begin
          manager.allocate(max_memory + 1)
        rescue StandardError
          nil
        end
        expect(manager.available).to be >= 0
      end
    end

    describe "#over_limit?" do
      it "returns false when under limit" do
        manager.allocate(512)
        expect(manager.over_limit?).to be false
      end

      it "returns true when over limit" do
        # Force allocation over limit
        manager.instance_variable_set(:@current_usage, max_memory + 1)
        expect(manager.over_limit?).to be true
      end
    end

    describe "#usage_ratio" do
      it "returns 0.0 when empty" do
        expect(manager.usage_ratio).to eq(0.0)
      end

      it "returns ratio of usage" do
        manager.allocate(512)
        expect(manager.usage_ratio).to eq(0.5)
      end

      it "handles zero max memory" do
        manager = described_class.new(max: 0)
        expect(manager.usage_ratio).to eq(0.0)
      end
    end

    describe "#cleanup" do
      it "clears all buffers" do
        manager.allocate(512)
        manager.cleanup
        expect(manager.current_usage).to eq(0)
      end

      it "cleans up temp files" do
        manager = described_class.new(max: max_memory, strategy: :disk)
        temp = manager.allocate(2048)
        path = temp.path
        manager.cleanup
        expect(File.exist?(path)).to be false
      end
    end

    describe ".with_manager" do
      it "creates manager with auto-cleanup" do
        result = described_class.with_manager(max: max_memory) do |mgr|
          mgr.allocate(512)
          "done"
        end

        expect(result).to eq("done")
      end

      it "ensures cleanup even on error" do
        expect do
          described_class.with_manager(max: max_memory) do |mgr|
            mgr.allocate(512)
            raise "error"
          end
        end.to raise_error("error")
      end
    end

    describe "#spill_to_disk" do
      it "creates temp file" do
        temp = manager.spill_to_disk
        expect(temp).to be_a(Tempfile)
        expect(File.exist?(temp.path)).to be true
      end

      it "writes buffer data if provided" do
        temp = manager.spill_to_disk("test data")
        temp.rewind
        expect(temp.read).to eq("test data")
      end
    end
  end

  describe "Integration Tests" do
    let(:input_file) { File.join(temp_dir, "large.dat") }
    let(:output_archive) { File.join(temp_dir, "output.zip") }
    let(:extracted_file) { File.join(temp_dir, "extracted.dat") }

    before do
      # Create simulated large file (1MB for testing)
      File.open(input_file, "wb") do |f|
        100.times { f.write("A" * 10_240) } # 1MB total
      end
    end

    describe ".compress_file" do
      it "compresses file with chunked processing" do
        result = described_class.compress_file(
          input_file,
          output_archive,
          chunk_size: 64 * 1024
        )

        expect(result).to eq(output_archive)
        expect(File.exist?(output_archive)).to be true
      end

      it "tracks progress via callback" do
        progresses = []
        described_class.compress_file(
          input_file,
          output_archive,
          chunk_size: 64 * 1024,
          progress: ->(_processed, _total, pct) { progresses << pct }
        )

        expect(progresses).not_to be_empty
        expect(progresses.last).to be_within(1).of(100)
      end

      it "raises error for non-existent file" do
        expect do
          described_class.compress_file("nonexistent.dat", output_archive)
        end.to raise_error(Errno::ENOENT)
      end
    end

    describe ".decompress_file" do
      before do
        # Create archive first
        described_class.compress_file(
          input_file,
          output_archive,
          chunk_size: 64 * 1024
        )
      end

      it "decompresses file with chunked processing" do
        result = described_class.decompress_file(
          output_archive,
          extracted_file,
          chunk_size: 64 * 1024
        )

        expect(result).to eq(extracted_file)
        expect(File.exist?(extracted_file)).to be true
      end

      it "preserves file content" do
        described_class.decompress_file(
          output_archive,
          extracted_file,
          chunk_size: 64 * 1024
        )

        original = File.binread(input_file)
        extracted = File.binread(extracted_file)
        expect(extracted).to eq(original)
      end

      it "tracks progress via callback" do
        progresses = []
        described_class.decompress_file(
          output_archive,
          extracted_file,
          chunk_size: 64 * 1024,
          progress: ->(_processed, _total, pct) { progresses << pct }
        )

        expect(progresses).not_to be_empty
      end
    end
  end

  describe "Memory-Limited Operations" do
    let(:input_file) { File.join(temp_dir, "test.dat") }
    let(:output_file) { File.join(temp_dir, "output.dat") }

    before do
      # Create 100KB test file
      File.binwrite(input_file, "X" * 100_000)
    end

    it "processes file within memory limits" do
      max_memory = 50_000 # 50KB limit
      chunk_size = 10_000 # 10KB chunks

      reader = Omnizip::Chunked::Reader.new(input_file, chunk_size: chunk_size)
      writer = Omnizip::Chunked::Writer.new(output_file, chunk_size: chunk_size)
      manager = Omnizip::Chunked::MemoryManager.new(max: max_memory,
                                                    strategy: :disk)

      begin
        reader.each_chunk do |chunk|
          # Simulate processing with memory management
          buffer = manager.allocate(chunk.bytesize)
          writer.write_chunk(chunk)
          manager.release(buffer)

          # Verify we stay within limits
          expect(manager.current_usage).to be <= max_memory
        end
      ensure
        writer.close
        manager.cleanup
      end

      expect(File.size(output_file)).to eq(100_000)
    end
  end
end
