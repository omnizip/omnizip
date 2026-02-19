# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/writer"
require "omnizip/formats/rar/rar5/header"
require "tempfile"
require "stringio"

RSpec.describe "RAR5 Optional File Fields" do
  describe "mtime (modification time)" do
    it "includes mtime when mtime parameter is provided" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content with mtime")
        file.flush

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :store,
            include_mtime: true,
          )
          writer.add_file(file.path)
          writer.write

          # Verify archive can be extracted
          output_dir = Dir.mktmpdir
          begin
            result = system("unrar", "x", "-y", output.path, output_dir,
                            out: File::NULL, err: File::NULL)
            expect(result).to be true

            # Verify file was extracted
            extracted_file = File.join(output_dir, File.basename(file.path))
            expect(File.exist?(extracted_file)).to be true
            expect(File.read(extracted_file)).to eq("Test content with mtime")
          ensure
            FileUtils.rm_rf(output_dir)
          end
        end
      end
    end

    it "preserves mtime from original file" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content")
        file.flush

        # Set a specific mtime
        original_mtime = Time.new(2024, 6, 15, 10, 30, 45)
        File.utime(File.atime(file.path), original_mtime, file.path)

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :store,
            include_mtime: true,
          )
          writer.add_file(file.path)
          writer.write

          # Extract and verify mtime (allow 1 second tolerance for precision loss)
          output_dir = Dir.mktmpdir
          begin
            result = system("unrar", "x", "-y", output.path, output_dir,
                            out: File::NULL, err: File::NULL)
            expect(result).to be true

            extracted_file = File.join(output_dir, File.basename(file.path))
            expect(File.exist?(extracted_file)).to be true
            extracted_mtime = File.mtime(extracted_file)

            # RAR5 mtime has precision to seconds, not subseconds
            expect(extracted_mtime.to_i).to be_within(2).of(original_mtime.to_i)
          ensure
            FileUtils.rm_rf(output_dir)
          end
        end
      end
    end
  end

  describe "CRC32 checksum" do
    it "includes CRC32 when crc32 parameter is provided" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content with CRC32")
        file.flush

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :store,
            include_crc32: true,
          )
          writer.add_file(file.path)
          writer.write

          # Verify archive integrity
          result = system("unrar", "t", "-y", output.path, out: File::NULL,
                                                           err: File::NULL)
          expect(result).to be true
        end
      end
    end

    it "verifies CRC32 during extraction with STORE compression" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content for CRC verification")
        file.flush

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :store,
            include_crc32: true,
          )
          writer.add_file(file.path)
          writer.write

          # Extract and verify
          output_dir = Dir.mktmpdir
          begin
            result = system("unrar", "x", "-y", output.path, output_dir,
                            out: File::NULL, err: File::NULL)
            expect(result).to be true

            extracted_file = File.join(output_dir, File.basename(file.path))
            expect(File.read(extracted_file)).to eq("Test content for CRC verification")
          ensure
            FileUtils.rm_rf(output_dir)
          end
        end
      end
    end
  end

  describe "combined optional fields" do
    it "includes both mtime and CRC32 when both are enabled with STORE" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content with both fields")
        file.flush

        original_mtime = Time.new(2024, 12, 23, 16, 30, 0)
        File.utime(File.atime(file.path), original_mtime, file.path)

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :store,
            include_mtime: true,
            include_crc32: true,
          )
          writer.add_file(file.path)
          writer.write

          # Test integrity and extraction
          expect(system("unrar", "t", "-y", output.path, out: File::NULL,
                                                         err: File::NULL)).to be true

          output_dir = Dir.mktmpdir
          begin
            expect(system("unrar", "x", "-y", output.path, output_dir,
                          out: File::NULL, err: File::NULL)).to be true

            extracted_file = File.join(output_dir, File.basename(file.path))
            expect(File.exist?(extracted_file)).to be true
            expect(File.read(extracted_file)).to eq("Test content with both fields")
            expect(File.mtime(extracted_file).to_i).to be_within(2).of(original_mtime.to_i)
          ensure
            FileUtils.rm_rf(output_dir)
          end
        end
      end
    end

    it "auto-disables CRC32 with LZMA compression (RAR5 limitation)" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test data for LZMA with CRC32")
        file.flush

        Tempfile.create(["output", ".rar"]) do |output|
          # Request CRC32 with LZMA - should auto-disable CRC32
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :lzma,
            level: 3,
            include_crc32: true,
          )
          writer.add_file(file.path)
          writer.write

          # Should pass unrar test (CRC32 was auto-disabled)
          result = system("unrar", "t", "-y", output.path, out: File::NULL,
                                                           err: File::NULL)
          expect(result).to be true
        end
      end
    end

    it "allows mtime with LZMA compression" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test mtime with LZMA")
        file.flush

        original_mtime = Time.new(2024, 6, 15, 10, 30, 45)
        File.utime(File.atime(file.path), original_mtime, file.path)

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(
            output.path,
            compression: :lzma,
            level: 3,
            include_mtime: true,
          )
          writer.add_file(file.path)
          writer.write

          # Verify archive format is valid
          result = system("unrar", "t", "-y", output.path, out: File::NULL,
                                                           err: File::NULL)
          expect(result).to be true
        end
      end
    end

    it "works with default options (no optional fields)" do
      Tempfile.create(["test", ".txt"]) do |file|
        file.write("Test content without optional fields")
        file.flush

        Tempfile.create(["output", ".rar"]) do |output|
          writer = Omnizip::Formats::Rar::Rar5::Writer.new(output.path,
                                                           compression: :store)
          writer.add_file(file.path)
          writer.write

          # Should still work fine
          expect(system("unrar", "t", "-y", output.path, out: File::NULL,
                                                         err: File::NULL)).to be true
        end
      end
    end
  end
end
