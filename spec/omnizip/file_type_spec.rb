# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Omnizip::FileType do
  describe ".detect" do
    it "detects MIME type from file path with extension" do
      Tempfile.create(["test", ".txt"]) do |f|
        f.write("Hello, world!")
        f.flush

        mime_type = described_class.detect(f.path)
        # Marcel may detect as text/plain or application/octet-stream
        expect(mime_type).to match(/text\/plain|application\/octet-stream/)
      end
    end

    it "detects MIME type from file path with magic bytes" do
      Tempfile.create(["test", ".dat"]) do |f|
        f.write("PK\x03\x04")
        f.write("zip content")
        f.flush

        mime_type = described_class.detect(f.path)
        expect(mime_type).to eq("application/zip")
      end
    end

    it "detects PDF files" do
      Tempfile.create(["test", ".pdf"]) do |f|
        f.write("%PDF-1.4\n")
        f.write("rest of pdf data")
        f.flush

        mime_type = described_class.detect(f.path)
        expect(mime_type).to eq("application/pdf")
      end
    end

    it "detects PNG images" do
      Tempfile.create(["test", ".png"], binmode: true) do |f|
        # Ensure binary mode on Windows
        f.binmode
        f.write("\x89PNG\r\n\x1A\n")
        f.write("rest of png data")
        f.flush
        f.close # Close to ensure data is written

        mime_type = described_class.detect(f.path)
        # Marcel behavior varies by platform - Windows may lack proper magic database
        if Gem.win_platform?
          expect(mime_type).to match(/image\/png|application\/octet-stream/)
        else
          expect(mime_type).to eq("image/png")
        end
      end
    end

    it "returns nil for non-existent file" do
      mime_type = described_class.detect("/nonexistent/file.txt")
      expect(mime_type).to be_nil
    end

    it "returns nil for nil path" do
      mime_type = described_class.detect(nil)
      expect(mime_type).to be_nil
    end
  end

  describe ".detect_data" do
    it "detects MIME type from binary data" do
      data = "PK\x03\x04zip content"
      mime_type = described_class.detect_data(data)
      expect(mime_type).to eq("application/zip")
    end

    it "detects MIME type with filename hint" do
      data = "Hello, world!"
      mime_type = described_class.detect_data(data, filename: "test.txt")
      expect(mime_type).to eq("text/plain")
    end

    it "detects PDF from data" do
      data = "%PDF-1.4\nrest of pdf"
      mime_type = described_class.detect_data(data)
      expect(mime_type).to eq("application/pdf")
    end

    it "detects PNG from data" do
      data = "\x89PNG\r\n\x1A\nrest of png"
      mime_type = described_class.detect_data(data)
      expect(mime_type).to eq("image/png")
    end

    it "detects JPEG from data" do
      data = "\xFF\xD8\xFFrest of jpeg"
      mime_type = described_class.detect_data(data)
      expect(mime_type).to eq("image/jpeg")
    end

    it "returns nil for nil data" do
      mime_type = described_class.detect_data(nil)
      expect(mime_type).to be_nil
    end

    it "returns nil for empty data" do
      mime_type = described_class.detect_data("")
      expect(mime_type).to be_nil
    end
  end

  describe ".detect_stream" do
    it "detects MIME type from IO stream" do
      io = StringIO.new("PK\x03\x04zip content")
      mime_type = described_class.detect_stream(io)
      expect(mime_type).to eq("application/zip")
      expect(io.pos).to eq(0) # Position restored
    end

    it "detects MIME type from stream with filename hint" do
      io = StringIO.new("Hello, world!")
      mime_type = described_class.detect_stream(io, filename: "test.txt")
      expect(mime_type).to eq("text/plain")
      expect(io.pos).to eq(0) # Position restored
    end

    it "detects from file IO" do
      Tempfile.create(["test", ".zip"]) do |f|
        f.write("PK\x03\x04")
        f.write("zip content")
        f.flush

        File.open(f.path, "rb") do |io|
          mime_type = described_class.detect_stream(io, filename: "test.zip")
          expect(mime_type).to eq("application/zip")
        end
      end
    end

    it "restores stream position after detection" do
      io = StringIO.new("PK\x03\x04zip content")
      io.seek(5) # Move to middle of stream

      described_class.detect_stream(io)
      expect(io.pos).to eq(5) # Position restored
    end

    it "returns nil for nil stream" do
      mime_type = described_class.detect_stream(nil)
      expect(mime_type).to be_nil
    end
  end

  describe Omnizip::FileType::MimeClassifier do
    describe ".text?" do
      it "identifies text/plain as text" do
        expect(described_class.text?("text/plain")).to be true
      end

      it "identifies text/html as text" do
        expect(described_class.text?("text/html")).to be true
      end

      it "identifies application/json as text" do
        expect(described_class.text?("application/json")).to be true
      end

      it "identifies text/* as text" do
        expect(described_class.text?("text/markdown")).to be true
      end

      it "does not identify archive as text" do
        expect(described_class.text?("application/zip")).to be false
      end

      it "returns false for nil" do
        expect(described_class.text?(nil)).to be false
      end
    end

    describe ".archive?" do
      it "identifies application/zip as archive" do
        expect(described_class.archive?("application/zip")).to be true
      end

      it "identifies application/x-7z-compressed as archive" do
        expect(described_class.archive?("application/x-7z-compressed")).to be true
      end

      it "identifies application/gzip as archive" do
        expect(described_class.archive?("application/gzip")).to be true
      end

      it "identifies application/x-tar as archive" do
        expect(described_class.archive?("application/x-tar")).to be true
      end

      it "does not identify text as archive" do
        expect(described_class.archive?("text/plain")).to be false
      end

      it "returns false for nil" do
        expect(described_class.archive?(nil)).to be false
      end
    end

    describe ".executable?" do
      it "identifies application/x-executable as executable" do
        expect(described_class.executable?("application/x-executable")).to be true
      end

      it "identifies application/x-elf as executable" do
        expect(described_class.executable?("application/x-elf")).to be true
      end

      it "identifies application/x-mach-binary as executable" do
        expect(described_class.executable?("application/x-mach-binary")).to be true
      end

      it "does not identify text as executable" do
        expect(described_class.executable?("text/plain")).to be false
      end

      it "returns false for nil" do
        expect(described_class.executable?(nil)).to be false
      end
    end

    describe ".media?" do
      it "identifies image/* as media" do
        expect(described_class.media?("image/png")).to be true
        expect(described_class.media?("image/jpeg")).to be true
      end

      it "identifies audio/* as media" do
        expect(described_class.media?("audio/mpeg")).to be true
      end

      it "identifies video/* as media" do
        expect(described_class.media?("video/mp4")).to be true
      end

      it "identifies application/pdf as media" do
        expect(described_class.media?("application/pdf")).to be true
      end

      it "does not identify text as media" do
        expect(described_class.media?("text/plain")).to be false
      end

      it "returns false for nil" do
        expect(described_class.media?(nil)).to be false
      end
    end

    describe ".profile_category" do
      it "returns :text for text MIME types" do
        expect(described_class.profile_category("text/plain")).to eq(:text)
        expect(described_class.profile_category("application/json")).to eq(:text)
      end

      it "returns :binary for executable MIME types" do
        expect(described_class.profile_category("application/x-executable")).to eq(:binary)
        expect(described_class.profile_category("application/x-elf")).to eq(:binary)
      end

      it "returns :archive for archive MIME types" do
        expect(described_class.profile_category("application/zip")).to eq(:archive)
        expect(described_class.profile_category("application/x-7z-compressed")).to eq(:archive)
      end

      it "returns :archive for media MIME types" do
        expect(described_class.profile_category("image/png")).to eq(:archive)
        expect(described_class.profile_category("video/mp4")).to eq(:archive)
      end

      it "returns :balanced for unknown MIME types" do
        expect(described_class.profile_category("application/unknown")).to eq(:balanced)
      end

      it "returns :balanced for nil" do
        expect(described_class.profile_category(nil)).to eq(:balanced)
      end
    end
  end
end
