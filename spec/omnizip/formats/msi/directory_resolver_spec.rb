# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::DirectoryResolver do
  describe "#resolve_path" do
    it "resolves simple directory path" do
      directory_table = [
        { "Directory" => "TARGETDIR", "Directory_Parent" => nil, "DefaultDir" => "SourceDir" },
        { "Directory" => "PFILES", "Directory_Parent" => "TARGETDIR", "DefaultDir" => "Program Files" },
        { "Directory" => "MYAPP", "Directory_Parent" => "PFILES", "DefaultDir" => "MyApp" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.resolve_path("TARGETDIR")).to eq("SourceDir")
      expect(resolver.resolve_path("PFILES")).to eq("SourceDir/Program Files")
      expect(resolver.resolve_path("MYAPP")).to eq("SourceDir/Program Files/MyApp")
    end

    it "handles DefaultDir with source|target format" do
      directory_table = [
        { "Directory" => "ROOT", "Directory_Parent" => nil, "DefaultDir" => "SourceDir" },
        { "Directory" => "APPDIR", "Directory_Parent" => "ROOT", "DefaultDir" => "appdir|My Application" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.resolve_path("APPDIR")).to eq("SourceDir/My Application")
    end

    it "returns empty string for nil key" do
      resolver = described_class.new([])

      expect(resolver.resolve_path(nil)).to eq("")
      expect(resolver.resolve_path("")).to eq("")
    end

    it "returns empty string for unknown directory" do
      resolver = described_class.new([])

      expect(resolver.resolve_path("UNKNOWN")).to eq("")
    end

    it "handles circular references" do
      # This shouldn't happen in valid MSIs, but we should handle it gracefully
      directory_table = [
        { "Directory" => "A", "Directory_Parent" => "B", "DefaultDir" => "DirA" },
        { "Directory" => "B", "Directory_Parent" => "A", "DefaultDir" => "DirB" },
      ]

      resolver = described_class.new(directory_table)

      # Should not infinite loop
      path = resolver.resolve_path("A")
      expect(path).to be_a(String)
    end
  end

  describe "#source_name" do
    it "extracts source name from DefaultDir" do
      directory_table = [
        { "Directory" => "TEST", "Directory_Parent" => nil, "DefaultDir" => "src|target" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.source_name("TEST")).to eq("src")
    end

    it "returns name when no separator" do
      directory_table = [
        { "Directory" => "TEST", "Directory_Parent" => nil, "DefaultDir" => "dirname" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.source_name("TEST")).to eq("dirname")
    end
  end

  describe "#target_name" do
    it "extracts target name from DefaultDir" do
      directory_table = [
        { "Directory" => "TEST", "Directory_Parent" => nil, "DefaultDir" => "src|target" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.target_name("TEST")).to eq("target")
    end

    it "returns name when no separator" do
      directory_table = [
        { "Directory" => "TEST", "Directory_Parent" => nil, "DefaultDir" => "dirname" },
      ]

      resolver = described_class.new(directory_table)

      expect(resolver.target_name("TEST")).to eq("dirname")
    end
  end
end
