# frozen_string_literal: true

RSpec.describe Omnizip do
  it "has a version number" do
    expect(Omnizip::VERSION).not_to be_nil
  end

  it "defines the base Error class" do
    expect(Omnizip::Error).to be < StandardError
  end

  it "defines CompressionError" do
    expect(Omnizip::CompressionError).to be < Omnizip::Error
  end

  it "defines FormatError" do
    expect(Omnizip::FormatError).to be < Omnizip::Error
  end

  it "defines IOError" do
    expect(Omnizip::IOError).to be < Omnizip::Error
  end

  describe "autoload" do
    it "loads Formats module" do
      expect(Omnizip::Formats).to be_a(Module)
    end

    it "autoloads SevenZip format" do
      expect(Omnizip::Formats::SevenZip).to be_a(Module)
    end

    it "autoloads Rar format" do
      expect(Omnizip::Formats::Rar).to be_a(Module)
    end

    it "autoloads Iso format" do
      expect(Omnizip::Formats::Iso).to be_a(Module)
    end

    it "autoloads Xz format" do
      expect(Omnizip::Formats::Xz).to be_a(Class)
    end
  end

  describe "convenience methods" do
    it "responds to compress_file" do
      expect(Omnizip).to respond_to(:compress_file)
    end

    it "responds to extract_archive" do
      expect(Omnizip).to respond_to(:extract_archive)
    end

    it "responds to list_archive" do
      expect(Omnizip).to respond_to(:list_archive)
    end
  end
end
