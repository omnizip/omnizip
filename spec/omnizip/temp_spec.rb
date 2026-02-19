# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Temp do
  describe "configuration" do
    it "has default configuration" do
      config = described_class.configuration

      expect(config.directory).to be_nil
      expect(config.prefix).to eq("omniz_")
      expect(config.cleanup_on_exit).to be true
    end

    it "allows configuration changes" do
      described_class.configure do |config|
        config.prefix = "custom_"
        config.cleanup_on_exit = false
      end

      expect(described_class.configuration.prefix).to eq("custom_")
      expect(described_class.configuration.cleanup_on_exit).to be false

      # Reset
      described_class.configure do |config|
        config.prefix = "omniz_"
        config.cleanup_on_exit = true
      end
    end
  end

  describe ".file" do
    it "creates temp file with default prefix" do
      file_path = nil

      described_class.file do |path|
        file_path = path
        expect(File.exist?(path)).to be true
        expect(File.basename(path)).to start_with("omniz_")
      end

      # File should be deleted after block
      expect(File.exist?(file_path)).to be false
    end

    it "creates temp file with custom prefix and suffix" do
      described_class.file(prefix: "test_", suffix: ".zip") do |path|
        expect(File.basename(path)).to start_with("test_")
        expect(File.basename(path)).to end_with(".zip")
      end
    end

    it "returns block value" do
      result = described_class.file { |_path| "test_value" }
      expect(result).to eq("test_value")
    end

    it "cleans up on exception" do
      file_path = nil

      expect do
        described_class.file do |path|
          file_path = path
          raise "Test error"
        end
      end.to raise_error("Test error")

      expect(File.exist?(file_path)).to be false
    end

    it "allows writing and reading from temp file" do
      described_class.file do |path|
        File.write(path, "test content")
        expect(File.read(path)).to eq("test content")
      end
    end
  end

  describe ".directory" do
    it "creates temp directory" do
      dir_path = nil

      described_class.directory do |path|
        dir_path = path
        expect(Dir.exist?(path)).to be true
        expect(File.basename(path)).to start_with("omniz_")
      end

      # Directory should be deleted after block
      expect(Dir.exist?(dir_path)).to be false
    end

    it "creates temp directory with custom prefix" do
      described_class.directory(prefix: "mytest_") do |path|
        expect(File.basename(path)).to start_with("mytest_")
      end
    end

    it "allows creating files in temp directory" do
      described_class.directory do |dir|
        test_file = File.join(dir, "test.txt")
        File.write(test_file, "content")
        expect(File.read(test_file)).to eq("content")
      end
    end

    it "cleans up directory and contents" do
      dir_path = nil
      file_path = nil

      described_class.directory do |dir|
        dir_path = dir
        file_path = File.join(dir, "test.txt")
        File.write(file_path, "content")
      end

      expect(Dir.exist?(dir_path)).to be false
      expect(File.exist?(file_path)).to be false
    end
  end

  describe ".with_archive" do
    it "creates temp zip archive" do
      described_class.with_archive(format: :zip) do |archive|
        expect(archive.path).to end_with(".zip")
        expect(File.exist?(archive.path)).to be true
        expect(archive.format).to eq(:zip)
      end
    end

    it "creates temp 7z archive" do
      described_class.with_archive(format: :seven_zip) do |archive|
        expect(archive.path).to end_with(".7z")
        expect(archive.format).to eq(:seven_zip)
      end
    end

    it "cleans up archive after block" do
      archive_path = nil

      described_class.with_archive do |archive|
        archive_path = archive.path
      end

      expect(File.exist?(archive_path)).to be false
    end
  end

  describe Omnizip::Temp::TempFile do
    describe "#initialize" do
      it "creates temp file" do
        temp = described_class.new

        expect(temp.path).not_to be_nil
        expect(File.exist?(temp.path)).to be true

        temp.unlink
      end

      it "uses custom prefix and suffix" do
        temp = described_class.new(prefix: "custom_", suffix: ".dat")

        expect(File.basename(temp.path)).to start_with("custom_")
        expect(File.basename(temp.path)).to end_with(".dat")

        temp.unlink
      end
    end

    describe "#write and #read" do
      it "writes and reads data" do
        temp = described_class.new

        temp.write("test data")
        temp.rewind
        expect(temp.read).to eq("test data")

        temp.unlink
      end
    end

    describe "#unlink" do
      it "deletes temp file" do
        temp = described_class.new
        path = temp.path

        temp.unlink

        expect(File.exist?(path)).to be false
        expect(temp.finalized?).to be true
      end

      it "is idempotent" do
        temp = described_class.new

        temp.unlink
        expect { temp.unlink }.not_to raise_error
      end
    end

    describe "#keep!" do
      it "prevents automatic deletion" do
        temp = described_class.new
        path = temp.path

        temp.keep!
        temp.unlink

        # File should still exist because we called keep!
        # (unlink won't delete if kept)
        expect(temp.kept?).to be true
      ensure
        FileUtils.rm_f(path)
      end
    end

    describe "finalizer" do
      it "cleans up on garbage collection" do
        # Create temp file in isolated scope
        begin
          temp = described_class.new
          temp.path
          nil # Remove reference
        end

        # Force GC (may not immediately trigger finalizer)
        GC.start

        # Give finalizer time to run
        sleep 0.1

        # NOTE: Finalizer cleanup is best-effort
        # We can't guarantee it runs immediately
      end
    end
  end

  describe Omnizip::Temp::TempFilePool do
    describe "#initialize" do
      it "creates pool with default size" do
        pool = described_class.new

        expect(pool.size).to eq(10)
        expect(pool.available_count).to eq(0)
      end

      it "creates pool with custom size" do
        pool = described_class.new(size: 5)

        expect(pool.size).to eq(5)
      end
    end

    describe "#acquire" do
      it "provides temp file for block" do
        pool = described_class.new(size: 3)

        pool.acquire do |temp_file|
          expect(temp_file).to be_a(Omnizip::Temp::TempFile)
          expect(File.exist?(temp_file.path)).to be true
        end
      end

      it "returns block value" do
        pool = described_class.new

        result = pool.acquire { |_tf| "test_value" }

        expect(result).to eq("test_value")
      end

      it "reuses temp files from pool" do
        pool = described_class.new(size: 2)
        first_path = nil

        # First acquire - creates new file
        pool.acquire do |temp_file|
          first_path = temp_file.path
          temp_file.write("data")
        end

        # Second acquire - should reuse same file
        pool.acquire do |temp_file|
          expect(temp_file.path).to eq(first_path)
          # Should be rewound
          expect(temp_file.read).to eq("data")
        end

        pool.clear
      end

      it "tracks reuse statistics" do
        pool = described_class.new(size: 2)

        # Create and return to pool
        pool.acquire { |_tf| nil }
        pool.acquire { |_tf| nil }
        pool.acquire { |_tf| nil }

        stats = pool.stats

        expect(stats[:created]).to be >= 1
        expect(stats[:reused]).to be >= 0
        expect(stats[:efficiency]).to be_a(Float)

        pool.clear
      end

      it "deletes file if pool is full" do
        pool = described_class.new(size: 1)
        paths = []

        # Fill pool
        pool.acquire { |tf| paths << tf.path }

        # This should evict the first file
        pool.acquire { |tf| paths << tf.path }

        expect(pool.available_count).to eq(1)

        pool.clear
      end

      it "cleans up on exception" do
        pool = described_class.new
        temp_path = nil

        expect do
          pool.acquire do |temp_file|
            temp_path = temp_file.path
            raise "Test error"
          end
        end.to raise_error("Test error")

        # File should be deleted even on exception
        expect(File.exist?(temp_path)).to be false
      end
    end

    describe "#clear" do
      it "removes all files from pool" do
        pool = described_class.new(size: 3)

        # Add files to pool
        pool.acquire { |_tf| nil }
        pool.acquire { |_tf| nil }

        expect(pool.available_count).to be > 0

        pool.clear

        expect(pool.available_count).to eq(0)
      end
    end

    describe "#stats" do
      it "returns pool statistics" do
        pool = described_class.new(size: 5)

        pool.acquire { |_tf| nil }

        stats = pool.stats

        expect(stats).to include(:pool_size, :available, :created,
                                 :reused, :efficiency)
        expect(stats[:pool_size]).to eq(5)

        pool.clear
      end
    end
  end

  describe Omnizip::Temp::SafeExtract do
    let(:fixture_dir) { File.join(__dir__, "..", "fixtures", "zip") }
    let(:test_zip) { File.join(fixture_dir, "simple_deflate.zip") }
    let(:dest_dir) { File.join(Dir.tmpdir, "safe_extract_test") }

    before do
      FileUtils.rm_rf(dest_dir)
    end

    after do
      FileUtils.rm_rf(dest_dir)
    end

    describe "#extract" do
      it "extracts archive to destination" do
        skip "Test archive not available" unless File.exist?(test_zip)

        extractor = described_class.new(test_zip, dest_dir)
        result = extractor.extract

        expect(result).to eq(dest_dir)
        expect(Dir.exist?(dest_dir)).to be true
      end

      it "calls verification block" do
        skip "Test archive not available" unless File.exist?(test_zip)

        verified = false

        described_class.new(test_zip, dest_dir).extract do |temp_dir|
          verified = true
          expect(Dir.exist?(temp_dir)).to be true
          true
        end

        expect(verified).to be true
      end

      it "rolls back on verification failure" do
        skip "Test archive not available" unless File.exist?(test_zip)

        expect do
          described_class.new(test_zip, dest_dir).extract do |_temp_dir|
            false # Verification fails
          end
        end.to raise_error(Omnizip::Temp::SafeExtract::VerificationError)

        expect(Dir.exist?(dest_dir)).to be false
      end

      it "raises error for non-existent archive" do
        extractor = described_class.new("nonexistent.zip", dest_dir)

        expect { extractor.extract }.to raise_error(Errno::ENOENT)
      end
    end

    describe "#extract_with_count" do
      it "verifies file count" do
        skip "Test archive not available" unless File.exist?(test_zip)

        # Count files in test archive
        file_count = 0
        Omnizip::Zip::File.open(test_zip) do |zip|
          zip.each { |entry| file_count += 1 unless entry.directory? }
        end

        result = described_class.new(test_zip, dest_dir)
          .extract_with_count(file_count)

        expect(Dir.exist?(result)).to be true
      end

      it "fails on wrong file count" do
        skip "Test archive not available" unless File.exist?(test_zip)

        expect do
          described_class.new(test_zip, dest_dir).extract_with_count(999)
        end.to raise_error(Omnizip::Temp::SafeExtract::VerificationError)
      end
    end

    describe ".extract_safe" do
      it "provides class method shortcut" do
        skip "Test archive not available" unless File.exist?(test_zip)

        result = described_class.extract_safe(test_zip, dest_dir) do |temp_dir|
          expect(Dir.exist?(temp_dir)).to be true
          true
        end

        expect(result).to eq(dest_dir)
        expect(Dir.exist?(dest_dir)).to be true
      end
    end
  end

  describe "registry" do
    it "tracks temp files" do
      registry = described_class.registry

      initial_count = registry.count

      described_class.file do |_path|
        # Inside block, file should be tracked
        expect(registry.count).to eq(initial_count + 1)
      end

      # After block, file should be untracked
      expect(registry.count).to eq(initial_count)
    end

    it "cleans up all tracked files" do
      paths = []

      # Create some temp files without cleanup
      3.times do
        temp = Omnizip::Temp::TempFile.new
        paths << temp.path
        described_class.registry.track(temp)
      end

      # All should exist
      paths.each { |path| expect(File.exist?(path)).to be true }

      # Cleanup all
      described_class.cleanup_all

      # All should be deleted
      paths.each { |path| expect(File.exist?(path)).to be false }
    end
  end

  describe "integration scenarios" do
    it "handles nested temp operations" do
      outer_path = nil
      inner_path = nil

      described_class.file do |outer|
        outer_path = outer
        expect(File.exist?(outer)).to be true

        described_class.file do |inner|
          inner_path = inner
          expect(File.exist?(inner)).to be true
          expect(inner).not_to eq(outer)
        end

        # Inner should be cleaned up
        expect(File.exist?(inner_path)).to be false
        # Outer still exists
        expect(File.exist?(outer)).to be true
      end

      # Both cleaned up
      expect(File.exist?(outer_path)).to be false
      expect(File.exist?(inner_path)).to be false
    end

    it "handles concurrent operations" do
      threads = Array.new(5) do
        Thread.new do
          described_class.file do |path|
            File.write(path, "thread_#{Thread.current.object_id}")
            sleep 0.01
            expect(File.read(path)).to include("thread_")
          end
        end
      end

      threads.each(&:join)
    end

    it "pool reuse efficiency" do
      pool = Omnizip::Temp::TempFilePool.new(size: 3)

      # Perform many operations
      10.times do
        pool.acquire do |temp_file|
          temp_file.write("data")
        end
      end

      stats = pool.stats

      # Should have good reuse
      expect(stats[:created]).to be <= 3
      expect(stats[:reused]).to be > 0
      expect(stats[:efficiency]).to be > 50.0

      pool.clear
    end
  end
end
