# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/external_writer"
require "omnizip/formats/rar/license_validator"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Formats::Rar::ExternalWriter do
  let(:temp_dir) { Dir.mktmpdir("omnizip_rar_test") }
  let(:output_path) { File.join(temp_dir, "test.rar") }
  let(:test_file) { File.join(temp_dir, "test.txt") }
  let(:test_dir) { File.join(temp_dir, "test_directory") }

  before do
    # Create test files
    File.write(test_file, "Hello, RAR!")
    FileUtils.mkdir_p(test_dir)
    File.write(File.join(test_dir, "file1.txt"), "File 1")
    File.write(File.join(test_dir, "file2.txt"), "File 2")

    # Mock license confirmation for tests
    allow(Omnizip::Formats::Rar::LicenseValidator).to receive(:license_confirmed?).and_return(true)
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe ".available?" do
    it "returns true if RAR executable is found" do
      allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
      expect(described_class.available?).to be true
    end

    it "returns false if RAR executable is not found" do
      allow(described_class).to receive(:find_rar_executable).and_return(nil)
      expect(described_class.available?).to be false
    end
  end

  describe ".info" do
    context "when RAR is available" do
      before do
        allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
        allow(Open3).to receive(:capture2e).and_return(["RAR 6.00 beta 1", nil])
      end

      it "returns executable information" do
        info = described_class.info
        expect(info[:available]).to be true
        expect(info[:executable]).to eq("/usr/bin/rar")
        expect(info[:version]).to eq("6.00")
      end
    end

    context "when RAR is not available" do
      before do
        allow(described_class).to receive(:find_rar_executable).and_return(nil)
      end

      it "returns unavailable status" do
        info = described_class.info
        expect(info[:available]).to be false
      end
    end
  end

  describe "#initialize" do
    context "when RAR is not available" do
      before do
        allow(described_class).to receive(:find_rar_executable).and_return(nil)
      end

      it "raises RarNotAvailableError" do
        expect {
          described_class.new(output_path)
        }.to raise_error(Omnizip::RarNotAvailableError)
      end
    end

    context "when license is not confirmed" do
      before do
        allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
        allow(Omnizip::Formats::Rar::LicenseValidator).to receive(:license_confirmed?).and_return(false)
        allow(Omnizip::Formats::Rar::LicenseValidator).to receive(:confirm_license!).and_return(false)
      end

      it "raises NotLicensedError" do
        expect {
          described_class.new(output_path)
        }.to raise_error(Omnizip::NotLicensedError)
      end
    end

    context "when RAR is available and licensed" do
      before do
        allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
      end

      it "creates writer instance" do
        writer = described_class.new(output_path)
        expect(writer).to be_a(described_class)
        expect(writer.output_path).to eq(output_path)
      end

      it "accepts compression options" do
        writer = described_class.new(output_path,
          compression: :best,
          solid: true,
          recovery: 5
        )
        expect(writer.options[:compression]).to eq(:best)
        expect(writer.options[:solid]).to be true
        expect(writer.options[:recovery]).to eq(5)
      end
    end
  end

  describe "#add_file" do
    let(:writer) do
      allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
      described_class.new(output_path)
    end

    it "adds file to archive" do
      writer.add_file(test_file)
      expect(writer.files).to have(1).item
      expect(writer.files.first[:source]).to eq(File.expand_path(test_file))
    end

    it "raises error if file does not exist" do
      expect {
        writer.add_file("nonexistent.txt")
      }.to raise_error(ArgumentError, /File not found/)
    end

    it "accepts custom archive path" do
      writer.add_file(test_file, "custom/path.txt")
      expect(writer.files.first[:archive_path]).to eq("custom/path.txt")
    end
  end

  describe "#add_directory" do
    let(:writer) do
      allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
      described_class.new(output_path)
    end

    it "adds directory to archive" do
      writer.add_directory(test_dir)
      expect(writer.directories).to have(1).item
      expect(writer.directories.first[:source]).to eq(File.expand_path(test_dir))
    end

    it "raises error if directory does not exist" do
      expect {
        writer.add_directory("nonexistent_dir")
      }.to raise_error(ArgumentError, /Directory not found/)
    end

    it "supports recursive option" do
      writer.add_directory(test_dir, recursive: false)
      expect(writer.directories.first[:recursive]).to be false
    end

    it "accepts custom archive path" do
      writer.add_directory(test_dir, archive_path: "custom/dir")
      expect(writer.directories.first[:archive_path]).to eq("custom/dir")
    end
  end

  describe "#write" do
    let(:writer) do
      allow(described_class).to receive(:find_rar_executable).and_return("/usr/bin/rar")
      described_class.new(output_path)
    end

    context "when RAR creation succeeds" do
      before do
        allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
      end

      it "creates RAR archive" do
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
      end

      it "tests archive if requested" do
        writer = described_class.new(output_path, test_after_create: true)
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3).with(
          "/usr/bin/rar", "a", "-m3", "-o+", output_path, anything
        ).and_return(["", "", double(success?: true)])

        expect(Open3).to receive(:capture3).with(
          "/usr/bin/rar", "t", output_path
        ).and_return(["", "", double(success?: true)])

        writer.write
      end
    end

    context "when RAR creation fails" do
      before do
        allow(Open3).to receive(:capture3).and_return(
          ["", "Error creating archive", double(success?: false)]
        )
      end

      it "raises error" do
        writer.add_file(test_file)
        expect {
          writer.write
        }.to raise_error(/RAR creation failed/)
      end
    end

    context "compression options" do
      before do
        allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
      end

      it "applies compression level" do
        writer = described_class.new(output_path, compression: :best)
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-m5")
          ["", "", double(success?: true)]
        end

        writer.write
      end

      it "creates solid archive" do
        writer = described_class.new(output_path, solid: true)
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-s")
          ["", "", double(success?: true)]
        end

        writer.write
      end

      it "adds recovery record" do
        writer = described_class.new(output_path, recovery: 5)
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-rr5%")
          ["", "", double(success?: true)]
        end

        writer.write
      end

      it "applies password protection" do
        writer = described_class.new(output_path, password: "secret")
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-psecret")
          ["", "", double(success?: true)]
        end

        writer.write
      end

      it "encrypts headers when requested" do
        writer = described_class.new(output_path,
          password: "secret",
          encrypt_headers: true
        )
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-psecret")
          expect(args).to include("-hp")
          ["", "", double(success?: true)]
        end

        writer.write
      end

      it "creates volume splits" do
        writer = described_class.new(output_path, volume_size: 1_000_000)
        writer.add_file(test_file)

        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("-v1000000b")
          ["", "", double(success?: true)]
        end

        writer.write
      end
    end
  end
end