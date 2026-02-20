# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# XZ Utils Tool Compatibility Tests
#
# IMPORTANT: We ONLY test against official XZ Utils (xz command).
#
# Reference: Official XZ Utils source at /Users/mulgogi/src/external/xz
#
RSpec.describe "XZ Utils Tool Compatibility", :tool_integration do
  # Fixtures are at spec/fixtures/xz_utils/
  let(:fixtures_dir) { File.join(__dir__, "../fixtures/xz_utils") }
  let(:good_dir) { File.join(fixtures_dir, "good") }
  let(:bad_dir) { File.join(fixtures_dir, "bad") }
  let(:reference_dir) { File.join(fixtures_dir, "reference") }

  # Test data for round-trip testing (constant for use in describe blocks)
  TEST_PATTERNS = {
    empty: "",
    single_byte: "A",
    small: "Hello World!",
    medium: "x" * 1000,
    large: "y" * 100_000,
    repeating: "ABCD" * 250,
    random_like: (0..255).map(&:chr).join * 10,
  }.freeze

  # ============================================
  # SECTION 1: XZ Utils Reference File Decoding
  # ============================================

  describe "decoding XZ Utils reference files" do
    context "with good XZ files" do
      # Find all good-*.xz files
      let(:good_xz_files) do
        files = Dir.glob(File.join(good_dir, "good-*.xz"))
        files += Dir.glob(File.join(fixtures_dir, "good-*.xz"))
        files.uniq
      end

      it "decodes all good XZ files successfully" do
        failures = []

        good_xz_files.each do |xz_file|
          Omnizip::Formats::Xz.decompress(xz_file)
          # If we get here, decoding succeeded
        rescue StandardError => e
          failures << "#{File.basename(xz_file)}: #{e.message}"
        end

        expect(failures).to be_empty,
                            "Failed to decode:\n#{failures.join("\n")}"
      end

      # Test specific important files
      context "check types" do
        it "decodes CRC32 check files" do
          file = File.join(good_dir, "good-1-check-crc32.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end

        it "decodes CRC64 check files" do
          file = File.join(good_dir, "good-1-check-crc64.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end

        it "decodes SHA256 check files" do
          file = File.join(good_dir, "good-1-check-sha256.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end
      end

      context "LZMA2 variants" do
        %w[
          good-1-lzma2-1.xz
          good-1-lzma2-2.xz
          good-1-lzma2-3.xz
          good-1-lzma2-4.xz
          good-1-lzma2-5.xz
        ].each do |filename|
          it "decodes #{filename}" do
            file = File.join(good_dir, filename)
            skip "File not found" unless File.exist?(file)

            expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
          end
        end
      end

      context "block structure" do
        it "decodes empty stream" do
          file = File.join(good_dir, "good-0-empty.xz")
          skip "File not found" unless File.exist?(file)

          result = Omnizip::Formats::Xz.extract(file)
          expect(result).to eq("")
        end

        it "decodes multi-block stream" do
          file = File.join(good_dir, "good-2-lzma2.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end
      end

      context "with filters" do
        it "decodes Delta + LZMA2" do
          file = File.join(good_dir, "good-1-delta-lzma2.tiff.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end

        it "decodes ARM64 + LZMA2" do
          file = File.join(good_dir, "good-1-arm64-lzma2-1.xz")
          skip "File not found" unless File.exist?(file)

          expect { Omnizip::Formats::Xz.extract(file) }.not_to raise_error
        end
      end
    end

    context "with bad XZ files" do
      let(:bad_xz_files) { Dir.glob(File.join(bad_dir, "*.xz")) }

      it "rejects all bad XZ files with appropriate errors" do
        unexpected_success = []

        bad_xz_files.each do |xz_file|
          Omnizip::Formats::Xz.decompress(xz_file)
          unexpected_success << File.basename(xz_file)
        rescue StandardError
          # Expected - file should be rejected
        end

        expect(unexpected_success).to be_empty,
                                      "These bad files were incorrectly accepted:\n#{unexpected_success.join("\n")}"
      end
    end

    context "with LZMA_Alone files" do
      %w[
        good-unknown_size-with_eopm.lzma
        good-known_size-without_eopm.lzma
        good-known_size-with_eopm.lzma
      ].each do |filename|
        it "decodes #{filename}" do
          file = File.join(reference_dir, filename)
          skip "File not found" unless File.exist?(file)

          expect do
            Omnizip::Formats::LzmaAlone.decompress(file)
          end.not_to raise_error
        rescue NameError
          pending "LZMA_Alone format not yet implemented"
        end
      end
    end
  end

  # ============================================
  # SECTION 2: Round-trip with xz tool
  # ============================================

  describe "round-trip compatibility with xz command" do
    around do |example|
      Dir.mktmpdir("omnizip_xz_test") do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end

    attr_reader :tmpdir

    def tmp_path(name)
      File.join(tmpdir, name)
    end

    def run_xz_command(args)
      system("xz #{args}", out: File::NULL, err: File::NULL)
    end

    TEST_PATTERNS.each do |name, data|
      context "with #{name} data (#{data.bytesize} bytes)" do
        let(:original_data) { data }
        let(:input_file) { tmp_path("input.txt") }
        let(:omnizip_output) { tmp_path("omnizip.xz") }
        let(:xtool_output) { tmp_path("xtool.xz") }
        let(:extracted_file) { tmp_path("extracted.txt") }

        before do
          File.binwrite(input_file, original_data)
        end

        it "creates XZ files that xz tool can decompress" do
          # Create XZ file with Omnizip (input is data, not file path)
          Omnizip::Formats::Xz.create(original_data, omnizip_output)

          # Verify with xz tool
          result = run_xz_command("-t #{omnizip_output}")
          expect(result).to be true

          # Decompress with xz tool
          FileUtils.cp(omnizip_output, "#{extracted_file}.xz")
          result = run_xz_command("-d #{extracted_file}.xz")
          expect(result).to be true

          # Verify content
          expect(File.binread(extracted_file)).to eq(original_data)
        end

        it "decompresses XZ files created by xz tool" do
          # Create XZ file with xz tool
          expect(run_xz_command("-k #{input_file}")).to be true
          FileUtils.mv("#{input_file}.xz", xtool_output)

          # Decompress with Omnizip
          result = Omnizip::Formats::Xz.decompress(xtool_output)
          expect(result).to eq(original_data)
        end
      end
    end
  end

  # ============================================
  # SECTION 3: Round-trip content verification
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
      original = (0..255).map(&:chr).join * 100 # 25,600 bytes
      original = original.force_encoding(Encoding::BINARY)
      xz_file = File.join(tmpdir, "output.xz")

      # Compress with Omnizip
      Omnizip::Formats::Xz.create(original, xz_file)

      # Decompress with Omnizip
      result = Omnizip::Formats::Xz.decompress(xz_file)

      expect(result.bytesize).to eq(original.bytesize)
      expect(result.bytes).to eq(original.bytes)
    end
  end
end
