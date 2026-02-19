# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Archive Commands" do
  let(:test_dir) { Dir.mktmpdir }
  let(:archive_path) { File.join(test_dir, "test.7z") }
  let(:output_dir) { File.join(test_dir, "output") }

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe Omnizip::Commands::ArchiveCreateCommand do
    let(:command) { described_class.new }

    context "with single file" do
      let(:test_file) { File.join(test_dir, "test.txt") }

      before do
        File.write(test_file, "Hello, World!")
      end

      it "creates archive from single file" do
        command.run(archive_path, test_file)

        expect(File.exist?(archive_path)).to be true
        expect(File.size(archive_path)).to be > 0
      end

      it "creates archive with verbose option" do
        cmd = described_class.new(verbose: true)
        expect { cmd.run(archive_path, test_file) }.to(
          output(/Creating archive/).to_stdout,
        )
      end
    end

    context "with multiple files" do
      let(:file1) { File.join(test_dir, "file1.txt") }
      let(:file2) { File.join(test_dir, "file2.txt") }

      before do
        File.write(file1, "Content 1")
        File.write(file2, "Content 2")
      end

      it "creates archive from multiple files" do
        command.run(archive_path, file1, file2)

        expect(File.exist?(archive_path)).to be true

        reader = Omnizip::Formats::SevenZip::Reader.new(archive_path).open
        expect(reader.entries.map(&:name)).to(
          match_array(["file1.txt", "file2.txt"]),
        )
      end
    end

    context "with directory" do
      let(:dir_path) { File.join(test_dir, "testdir") }

      before do
        FileUtils.mkdir_p(dir_path)
        File.write(File.join(dir_path, "file1.txt"), "Content 1")
        File.write(File.join(dir_path, "file2.txt"), "Content 2")
      end

      it "creates archive from directory" do
        command.run(archive_path, dir_path)

        expect(File.exist?(archive_path)).to be true

        reader = Omnizip::Formats::SevenZip::Reader.new(archive_path).open
        names = reader.entries.map(&:name)
        expect(names).to include("testdir/")
        expect(names).to include("testdir/file1.txt")
        expect(names).to include("testdir/file2.txt")
      end
    end

    context "with different algorithms" do
      let(:test_file) { File.join(test_dir, "test.txt") }

      before do
        File.write(test_file, "Test content for compression")
      end

      it "creates archive with LZMA algorithm" do
        cmd = described_class.new(algorithm: "lzma")
        cmd.run(archive_path, test_file)

        expect(File.exist?(archive_path)).to be true
      end

      it "creates archive with LZMA2 algorithm" do
        cmd = described_class.new(algorithm: "lzma2")
        cmd.run(archive_path, test_file)

        expect(File.exist?(archive_path)).to be true
      end
    end

    context "with compression options" do
      let(:test_file) { File.join(test_dir, "test.txt") }

      before do
        File.write(test_file, "Test content" * 100)
      end

      it "creates archive with custom level" do
        cmd = described_class.new(level: 9)
        cmd.run(archive_path, test_file)

        expect(File.exist?(archive_path)).to be true
      end

      it "creates non-solid archive" do
        cmd = described_class.new(solid: false)
        cmd.run(archive_path, test_file)

        expect(File.exist?(archive_path)).to be true
      end
    end

    context "with error handling" do
      it "raises error for missing input" do
        expect do
          command.run(archive_path)
        end.to raise_error(Omnizip::IOError, /No input files/)
      end

      it "raises error for non-existent file" do
        expect do
          command.run(archive_path, "nonexistent.txt")
        end.to raise_error(Omnizip::IOError, /not found/)
      end
    end
  end

  describe Omnizip::Commands::ArchiveExtractCommand do
    let(:command) { described_class.new }
    let(:fixture_archive) do
      File.expand_path("../../fixtures/seven_zip/multi_file.7z",
                       __dir__)
    end

    before do
      FileUtils.mkdir_p(output_dir)
    end

    it "extracts archive to directory" do
      command.run(fixture_archive, output_dir)

      expect(Dir.exist?(output_dir)).to be true
      expect(Dir.glob(File.join(output_dir, "**/*")).any?).to be true
    end

    it "extracts archive with verbose option" do
      cmd = described_class.new(verbose: true)
      expect { cmd.run(fixture_archive, output_dir) }.to(
        output(/Extracting/).to_stdout,
      )
    end

    it "extracts to current directory when no output specified" do
      Dir.chdir(test_dir) do
        cmd = described_class.new
        cmd.run(fixture_archive)
      end

      # Check files were extracted somewhere
      expect(Dir.glob(File.join(test_dir, "**/*")).any?).to be true
    end

    context "with error handling" do
      it "raises error for missing archive" do
        expect do
          command.run("nonexistent.7z", output_dir)
        end.to raise_error(Omnizip::IOError, /not found/)
      end
    end
  end

  describe Omnizip::Commands::ArchiveListCommand do
    let(:command) { described_class.new }
    let(:fixture_archive) do
      File.expand_path("../../fixtures/seven_zip/multi_file.7z",
                       __dir__)
    end

    it "lists archive contents" do
      expect { command.run(fixture_archive) }.to(
        output(/Archive:/).to_stdout,
      )
    end

    it "lists archive with verbose option" do
      cmd = described_class.new(verbose: true)
      expect { cmd.run(fixture_archive) }.to(
        output(/Type.*Size.*Compressed.*Modified.*Name/).to_stdout,
      )
    end

    it "shows summary statistics" do
      expect { command.run(fixture_archive) }.to(
        output(/Summary:/).to_stdout,
      )
    end

    context "with error handling" do
      it "raises error for missing archive" do
        expect do
          command.run("nonexistent.7z")
        end.to raise_error(Omnizip::IOError, /not found/)
      end
    end
  end

  describe "Integration: Create and Extract" do
    let(:test_file1) { File.join(test_dir, "file1.txt") }
    let(:test_file2) { File.join(test_dir, "file2.txt") }
    let(:content1) { "This is test file 1" }
    let(:content2) { "This is test file 2" }

    before do
      File.write(test_file1, content1)
      File.write(test_file2, content2)
      FileUtils.mkdir_p(output_dir)
    end

    it "round-trips files through archive" do
      create_cmd = Omnizip::Commands::ArchiveCreateCommand.new
      create_cmd.run(archive_path, test_file1, test_file2)

      extract_cmd = Omnizip::Commands::ArchiveExtractCommand.new
      extract_cmd.run(archive_path, output_dir)

      extracted1 = File.join(output_dir, "file1.txt")
      extracted2 = File.join(output_dir, "file2.txt")

      expect(File.read(extracted1)).to eq(content1)
      expect(File.read(extracted2)).to eq(content2)
    end
  end
end
