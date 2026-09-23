# frozen_string_literal: true

require "spec_helper"
require "tempfile"

ORACLE = File.expand_path("../../../../fixtures/rar/oracle", __dir__).freeze

RSpec.describe "RAR5 Writer Integration" do
  let(:output_file) { Tempfile.new(["test", ".rar"]) }

  after { output_file.close! }

  describe "minimal empty archive" do
    it "creates valid empty archive" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.write

      # Verify file exists and is non-empty
      expect(File).to exist(output_file.path)
      expect(File.size(output_file.path)).to be > 8

      # Verify RAR5 signature
      sig = File.binread(output_file.path, 8)
      expect(sig).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")
    end

    it "has correct header structure" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.write

      data = File.binread(output_file.path)

      # RAR5 signature (8 bytes)
      expect(data[0..7]).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")

      # Main header follows signature
      # Byte 8: CRC32 (4 bytes)
      # Byte 12+: Header size (VINT), Type (VINT), Flags (VINT)
      expect(data.bytesize).to be >= 20 # Minimum: sig + main + end
    end
  end

  describe "archive with single file" do
    let(:test_file) { Tempfile.new("input.txt") }

    before do
      test_file.write("Hello, RAR5!")
      test_file.close
    end

    after { test_file.unlink }

    it "creates archive with file" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "hello.txt")
      writer.write

      # Verify archive created
      expect(File).to exist(output_file.path)
      expect(File.size(output_file.path)).to be > 50

      # Verify signature
      sig = File.binread(output_file.path, 8)
      expect(sig).to eq("\x52\x61\x72\x21\x1A\x07\x01\x00")
    end

    it "includes uncompressed file data" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "test.txt")
      writer.write

      data = File.binread(output_file.path)

      # File content should be present (STORE = uncompressed)
      expect(data).to include("Hello, RAR5!")
    end
  end

  describe "archive with multiple files" do
    let(:file1) { Tempfile.new("file1.txt") }
    let(:file2) { Tempfile.new("file2.txt") }

    before do
      file1.write("First file content")
      file1.close
      file2.write("Second file content")
      file2.close
    end

    after do
      file1.unlink
      file2.unlink
    end

    it "creates archive with multiple files" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(file1.path, "file1.txt")
      writer.add_file(file2.path, "file2.txt")
      writer.write

      expect(File).to exist(output_file.path)

      data = File.binread(output_file.path)
      expect(data).to include("First file content")
      expect(data).to include("Second file content")
    end
  end

  describe "oracle-frozen compatibility" do
    # The archive these examples produce was validated once by the unrar
    # CLI (list + extract) and frozen into spec/fixtures/rar/oracle by
    # scripts/generate_rar_oracle_fixtures.rb — no oracle at runtime.
    let(:frozen) { File.join(ORACLE, "rar5_single.rar") }
    let(:test_file) { Tempfile.new("input.txt") }

    before do
      skip "oracle fixtures missing" unless File.exist?(frozen)

      test_file.binmode
      test_file.write("Test content for unrar")
      test_file.close
    end

    after { test_file.unlink }

    it "matches the unrar-validated fixture byte-for-byte" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(output_file.path)
      writer.add_file(test_file.path, "test.txt")
      writer.write

      expect(File.binread(output_file.path)).to eq(File.binread(frozen))
    end

    it "the frozen listing shows a valid RAR 5 archive with the entry" do
      listing = File.read(File.join(ORACLE, "rar5_single.unrar-l.txt"))

      expect(listing).to include("Details: RAR 5")
      expect(listing).to include("test.txt")
      expect(listing).not_to match(/corrupt|ERROR|Unexpected end of archive/)
    end
  end
end
