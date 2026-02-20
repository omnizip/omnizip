# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# 7-Zip Tool Compatibility Tests
#
# IMPORTANT: We ONLY test against official 7-Zip (7zz command).
# p7zip is DEPRECATED and should NOT be used for testing.
#
# Reference: Official 7-Zip source at /Users/mulgogi/src/external/7-Zip
#
RSpec.describe "7-Zip Tool Compatibility", :tool_integration do
  let(:fixtures_dir) { File.expand_path("../fixtures/seven_zip", __dir__) }
  let(:reference_dir) { File.join(fixtures_dir, "reference") }
  let(:comprehensive_dir) { File.join(fixtures_dir, "reference_comprehensive") }

  # Test data patterns for round-trip testing (constant for use in describe blocks)
  TEST_PATTERNS = {
    empty: "",
    single_byte: "A",
    small: "Hello World!",
    medium: "x" * 1000,
    large: "y" * 100_000,
    repeating: "ABCD" * 250,
    random_like: (0..255).map(&:chr).join * 10,
  }.freeze

  # Check if official 7-Zip (7zz) tool is available
  def seven_zip_available?
    system("which 7zz", out: File::NULL, err: File::NULL)
  end

  # Use 7zz (official 7-Zip) NOT 7z (deprecated p7zip)
  def run_7zz_command(args)
    system("7zz #{args}", out: File::NULL, err: File::NULL)
  end

  def run_7zz_test(archive_path)
    system("7zz t #{archive_path}", out: File::NULL, err: File::NULL)
  end

  def run_7zz_list(archive_path)
    output = `7zz l #{archive_path} 2>/dev/null`
    output.split("\n")
  end

  def run_7zz_extract(archive_path, output_dir)
    system("7zz x -o#{output_dir} -y #{archive_path}", out: File::NULL, err: File::NULL)
  end

  # ============================================
  # SECTION 1: 7-Zip Reference File Decoding
  # ============================================

  describe "decoding 7-Zip reference files" do
    context "with COPY method archives (uncompressed)" do
      it "decodes small_copy.7z" do
        file = File.join(reference_dir, "small_copy.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files).not_to be_empty
        end
      end

      it "decodes medium_copy.7z" do
        file = File.join(reference_dir, "medium_copy.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files).not_to be_empty
        end
      end

      it "decodes multi_copy_nonsolid.7z" do
        file = File.join(reference_dir, "multi_copy_nonsolid.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files.length).to be >= 2
        end
      end
    end

    context "with LZMA2 compressed archives" do
      %w[
        small_lzma2.7z
        small_lzma2_ultra.7z
        medium_lzma2.7z
        large_lzma2.7z
      ].each do |filename|
        it "decodes #{filename}" do
          file = File.join(reference_dir, filename)
          skip "File not found" unless File.exist?(file)

          Omnizip::Formats::SevenZip.open(file) do |reader|
            expect(reader).to be_valid
            files = reader.list_files
            expect(files).not_to be_empty
          end
        end
      end

      it "decodes multi_lzma2_solid.7z (solid archive)" do
        file = File.join(reference_dir, "multi_lzma2_solid.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files.length).to be >= 2
        end
      end

      it "decodes multi_lzma2_nonsolid.7z (non-solid archive)" do
        file = File.join(reference_dir, "multi_lzma2_nonsolid.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files.length).to be >= 2
        end
      end
    end

    context "with edge case archives" do
      it "decodes empty.7z (empty archive)" do
        file = File.join(reference_dir, "empty.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
        end
      end

      it "decodes single_byte.7z" do
        file = File.join(reference_dir, "single_byte.7z")
        skip "File not found" unless File.exist?(file)

        Omnizip::Formats::SevenZip.open(file) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files).not_to be_empty
        end
      end
    end

    context "with existing fixture files" do
      %w[
        simple_copy.7z
        simple_lzma.7z
        simple_lzma2.7z
        multi_file.7z
        with_directory.7z
      ].each do |filename|
        it "decodes #{filename}" do
          file = File.join(fixtures_dir, filename)
          skip "File not found" unless File.exist?(file)

          Omnizip::Formats::SevenZip.open(file) do |reader|
            expect(reader).to be_valid
          end
        end
      end
    end
  end

  # ============================================
  # SECTION 2: Round-trip with 7zz tool (official 7-Zip)
  # ============================================

  describe "round-trip compatibility with 7zz command (official 7-Zip)" do
    around do |example|
      skip "7zz (official 7-Zip) not available" unless seven_zip_available?

      Dir.mktmpdir("omnizip_7zz_test") do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    attr_reader :tmpdir

    def tmp_path(name)
      File.join(tmpdir, name)
    end

    TEST_PATTERNS.except(:large).each do |name, data|
      context "with #{name} data (#{data.bytesize} bytes)" do
        let(:original_data) { data }
        let(:input_file) { tmp_path("input.txt") }
        let(:omnizip_output) { tmp_path("omnizip.7z") }
        let(:extract_dir) { tmp_path("extracted") }

        before do
          File.binwrite(input_file, original_data)
          FileUtils.mkdir_p(extract_dir)
        end

        it "creates 7z files that 7zz can list" do
          # Create 7z archive with Omnizip (solid LZMA2 mode - default)
          Omnizip::Formats::SevenZip.create(omnizip_output) do |writer|
            writer.add_file(input_file, "input.txt")
          end

          # Verify archive exists
          expect(File.exist?(omnizip_output)).to be true

          # Verify with 7zz tool - test command
          success = run_7zz_test(omnizip_output)
          expect(success).to be true
        end

        it "creates 7z files that 7zz can extract" do
          # Create 7z archive with Omnizip (solid LZMA2 mode - default)
          Omnizip::Formats::SevenZip.create(omnizip_output) do |writer|
            writer.add_file(input_file, "input.txt")
          end

          # Extract with 7zz tool
          success = run_7zz_extract(omnizip_output, extract_dir)
          expect(success).to be true

          # Verify extracted content
          extracted_file = File.join(extract_dir, "input.txt")
          expect(File.exist?(extracted_file)).to be true
          expect(File.binread(extracted_file)).to eq(original_data)
        end

        it "extracts 7z files created by 7zz tool" do
          # Create 7z archive with 7zz tool (official 7-Zip)
          expect(run_7zz_command("a #{omnizip_output} #{input_file}")).to be true

          # Read with Omnizip
          Omnizip::Formats::SevenZip.open(omnizip_output) do |reader|
            expect(reader).to be_valid
            files = reader.list_files
            expect(files).not_to be_empty
          end
        end
      end
    end

    context "with multi-file archives" do
      let(:file1) { tmp_path("file1.txt") }
      let(:file2) { tmp_path("file2.txt") }
      let(:data1) { "First file content\n" * 50 }
      let(:data2) { "Second file content\n" * 50 }
      let(:omnizip_output) { tmp_path("multi.7z") }
      let(:extract_dir) { tmp_path("extracted_multi") }

      before do
        File.binwrite(file1, data1)
        File.binwrite(file2, data2)
        FileUtils.mkdir_p(extract_dir)
      end

      it "creates multi-file solid archives that 7zz can extract" do
        # Create multi-file archive with Omnizip (solid mode - default)
        Omnizip::Formats::SevenZip.create(omnizip_output) do |writer|
          writer.add_file(file1, "file1.txt")
          writer.add_file(file2, "file2.txt")
        end

        # Verify with 7zz tool
        expect(run_7zz_test(omnizip_output)).to be true

        # Extract and verify
        expect(run_7zz_extract(omnizip_output, extract_dir)).to be true

        expect(File.binread(File.join(extract_dir, "file1.txt"))).to eq(data1)
        expect(File.binread(File.join(extract_dir, "file2.txt"))).to eq(data2)
      end
    end
  end

  # ============================================
  # SECTION 3: Content Integrity Verification
  # ============================================

  describe "content integrity" do
    around do |example|
      Dir.mktmpdir("omnizip_content_test") do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    attr_reader :tmpdir

    it "preserves exact byte content through round-trip" do
      original = (0..255).map(&:chr).join * 10 # 2,560 bytes
      input_file = File.join(tmpdir, "input.bin")
      archive_file = File.join(tmpdir, "output.7z")
      extract_dir = File.join(tmpdir, "extracted")

      File.binwrite(input_file, original)
      FileUtils.mkdir_p(extract_dir)

      # Compress with Omnizip
      Omnizip::Formats::SevenZip.create(archive_file, solid: false) do |writer|
        writer.add_file(input_file, "input.bin")
      end

      # Read back with Omnizip
      Omnizip::Formats::SevenZip.open(archive_file) do |reader|
        expect(reader).to be_valid
      end

      # If 7zz tool available, verify extraction
      if seven_zip_available?
        expect(run_7zz_extract(archive_file, extract_dir)).to be true
        extracted = File.binread(File.join(extract_dir, "input.bin"))
        expect(extracted.bytesize).to eq(original.bytesize)
        expect(extracted).to eq(original)
      end
    end

    it "handles binary data correctly" do
      # Binary data with all byte values
      binary_data = (0..255).to_a.pack("C*") * 100
      input_file = File.join(tmpdir, "binary.bin")
      archive_file = File.join(tmpdir, "binary.7z")

      File.binwrite(input_file, binary_data)

      Omnizip::Formats::SevenZip.create(archive_file, solid: false) do |writer|
        writer.add_file(input_file, "binary.bin")
      end

      Omnizip::Formats::SevenZip.open(archive_file) do |reader|
        expect(reader).to be_valid
      end
    end

    it "handles UTF-8 filenames correctly" do
      content = "Hello UTF-8"
      input_file = File.join(tmpdir, "test.txt")
      archive_file = File.join(tmpdir, "utf8.7z")
      utf8_name = "日本語ファイル.txt"

      File.binwrite(input_file, content)

      Omnizip::Formats::SevenZip.create(archive_file, solid: false) do |writer|
        writer.add_file(input_file, utf8_name)
      end

      Omnizip::Formats::SevenZip.open(archive_file) do |reader|
        files = reader.list_files
        expect(files.map(&:name)).to include(utf8_name)
      end
    end
  end

  # ============================================
  # SECTION 4: Archive Mode Tests
  # ============================================

  describe "archive modes" do
    around do |example|
      Dir.mktmpdir("omnizip_mode_test") do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    attr_reader :tmpdir

    context "non-solid mode" do
      it "creates valid non-solid archives" do
        file1 = File.join(tmpdir, "a.txt")
        file2 = File.join(tmpdir, "b.txt")
        archive = File.join(tmpdir, "nonsolid.7z")

        File.binwrite(file1, "Content A")
        File.binwrite(file2, "Content B")

        Omnizip::Formats::SevenZip.create(archive, solid: false) do |writer|
          writer.add_file(file1, "a.txt")
          writer.add_file(file2, "b.txt")
        end

        Omnizip::Formats::SevenZip.open(archive) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files.length).to eq(2)
        end

        if seven_zip_available?
          expect(run_7zz_test(archive)).to be true
        end
      end
    end

    context "solid mode" do
      it "creates valid solid archives" do
        file1 = File.join(tmpdir, "a.txt")
        file2 = File.join(tmpdir, "b.txt")
        archive = File.join(tmpdir, "solid.7z")

        File.binwrite(file1, "Content A" * 100)
        File.binwrite(file2, "Content B" * 100)

        Omnizip::Formats::SevenZip.create(archive, solid: true) do |writer|
          writer.add_file(file1, "a.txt")
          writer.add_file(file2, "b.txt")
        end

        Omnizip::Formats::SevenZip.open(archive) do |reader|
          expect(reader).to be_valid
          files = reader.list_files
          expect(files.length).to eq(2)
        end
      end
    end
  end

  # ============================================
  # SECTION 5: Error Handling
  # ============================================

  describe "error handling" do
    it "rejects non-7z files" do
      Tempfile.create(["test", ".7z"]) do |f|
        f.write("This is not a 7z file")
        f.close

        expect do
          Omnizip::Formats::SevenZip.open(f.path, &:list_files)
        end.to raise_error(StandardError)
      end
    end

    it "handles missing files gracefully" do
      expect do
        Omnizip::Formats::SevenZip.open("/nonexistent/path/file.7z")
      end.to raise_error(Errno::ENOENT)
    end

    it "handles corrupted archives" do
      Tempfile.create(["corrupt", ".7z"]) do |f|
        # Write a valid-looking but corrupt header
        f.write("7z\xbc\xaf\x27\x1c") # Valid signature
        f.write("\x00" * 100) # But corrupt rest
        f.close

        expect do
          Omnizip::Formats::SevenZip.open(f.path, &:list_files)
        end.to raise_error(StandardError)
      end
    end
  end

  # ============================================
  # SECTION 6: Comprehensive Fixture Tests
  # ============================================

  describe "comprehensive fixtures created by 7zz" do
    context "with single file archives" do
      %w[single_lzma2_mx5 single_lzma2_mx1 single_lzma2_mx9 single_lzma_mx5
         single_copy].each do |name|
        it "decodes #{name}.7z" do
          file = File.join(comprehensive_dir, "#{name}.7z")
          skip "Fixture not found: #{file}" unless File.exist?(file)

          Omnizip::Formats::SevenZip.open(file) do |reader|
            expect(reader).to be_valid
            files = reader.list_files
            expect(files).not_to be_empty
            expect(files.first.name).to include("test_data")
          end
        end
      end
    end

    context "with multi-file archives" do
      %w[multi_solid_lzma2 multi_nonsolid_lzma2 multi_copy with_empty_file
         with_directory].each do |name|
        it "decodes #{name}.7z" do
          file = File.join(comprehensive_dir, "#{name}.7z")
          skip "Fixture not found: #{file}" unless File.exist?(file)

          Omnizip::Formats::SevenZip.open(file) do |reader|
            expect(reader).to be_valid
            files = reader.list_files
            expect(files.length).to be >= 1
          end
        end
      end
    end
  end
end
