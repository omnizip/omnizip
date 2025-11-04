# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::LinkHandler::SymbolicLink do
  describe "#initialize" do
    it "creates a symbolic link with target" do
      link = described_class.new(target: "/path/to/target")
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to be_nil
    end

    it "creates a symbolic link with target and path" do
      link = described_class.new(target: "/path/to/target", path: "/path/to/link")
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to eq("/path/to/link")
    end
  end

  describe "#permissions" do
    it "returns symlink permissions (0120777)" do
      link = described_class.new(target: "/target")
      expect(link.permissions).to eq(0o120777)
    end
  end

  describe "#serialize" do
    it "returns the target path" do
      link = described_class.new(target: "/path/to/target")
      expect(link.serialize).to eq("/path/to/target")
    end
  end

  describe ".deserialize" do
    it "creates a symbolic link from serialized data" do
      link = described_class.deserialize("/path/to/target")
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to be_nil
    end

    it "creates a symbolic link with path" do
      link = described_class.deserialize("/path/to/target", path: "/link")
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to eq("/link")
    end
  end

  describe "#symlink?" do
    it "returns true" do
      link = described_class.new(target: "/target")
      expect(link.symlink?).to be true
    end
  end

  describe "#hardlink?" do
    it "returns false" do
      link = described_class.new(target: "/target")
      expect(link.hardlink?).to be false
    end
  end

  describe "#link_type" do
    it "returns 'symlink'" do
      link = described_class.new(target: "/target")
      expect(link.link_type).to eq("symlink")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      link = described_class.new(target: "/path/to/target", path: "/link")
      hash = link.to_h

      expect(hash[:type]).to eq(:symlink)
      expect(hash[:target]).to eq("/path/to/target")
      expect(hash[:path]).to eq("/link")
      expect(hash[:permissions]).to eq(0o120777)
    end
  end

  describe "#to_s" do
    it "returns string representation" do
      link = described_class.new(target: "/target", path: "/link")
      expect(link.to_s).to eq("/link -> /target (symlink)")
    end
  end

  describe "#inspect" do
    it "returns inspect representation" do
      link = described_class.new(target: "/target", path: "/link")
      expect(link.inspect).to include("SymbolicLink")
      expect(link.inspect).to include("/target")
      expect(link.inspect).to include("/link")
    end
  end
end