# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::LinkHandler::HardLink do
  describe "#initialize" do
    it "creates a hard link with target" do
      link = described_class.new(target: "/path/to/target")
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to be_nil
      expect(link.inode).to be_nil
    end

    it "creates a hard link with target, path, and inode" do
      link = described_class.new(
        target: "/path/to/target",
        path: "/path/to/link",
        inode: 12345,
      )
      expect(link.target).to eq("/path/to/target")
      expect(link.path).to eq("/path/to/link")
      expect(link.inode).to eq(12345)
    end
  end

  describe "#serialize" do
    it "returns hash with target and inode" do
      link = described_class.new(target: "/target", inode: 12345)
      serialized = link.serialize

      expect(serialized).to be_a(Hash)
      expect(serialized[:target]).to eq("/target")
      expect(serialized[:inode]).to eq(12345)
    end

    it "handles nil inode" do
      link = described_class.new(target: "/target")
      serialized = link.serialize

      expect(serialized[:target]).to eq("/target")
      expect(serialized[:inode]).to be_nil
    end
  end

  describe ".deserialize" do
    it "creates hard link from hash data" do
      data = { target: "/target", inode: 12345 }
      link = described_class.deserialize(data)

      expect(link.target).to eq("/target")
      expect(link.inode).to eq(12345)
      expect(link.path).to be_nil
    end

    it "creates hard link from hash with string keys" do
      data = { "target" => "/target", "inode" => 12345 }
      link = described_class.deserialize(data)

      expect(link.target).to eq("/target")
      expect(link.inode).to eq(12345)
    end

    it "creates hard link from legacy string format" do
      link = described_class.deserialize("/target")

      expect(link.target).to eq("/target")
      expect(link.inode).to be_nil
    end

    it "accepts path parameter" do
      data = { target: "/target", inode: 12345 }
      link = described_class.deserialize(data, path: "/link")

      expect(link.path).to eq("/link")
    end
  end

  describe "#symlink?" do
    it "returns false" do
      link = described_class.new(target: "/target")
      expect(link.symlink?).to be false
    end
  end

  describe "#hardlink?" do
    it "returns true" do
      link = described_class.new(target: "/target")
      expect(link.hardlink?).to be true
    end
  end

  describe "#link_type" do
    it "returns 'hardlink'" do
      link = described_class.new(target: "/target")
      expect(link.link_type).to eq("hardlink")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      link = described_class.new(
        target: "/path/to/target",
        path: "/link",
        inode: 12345,
      )
      hash = link.to_h

      expect(hash[:type]).to eq(:hardlink)
      expect(hash[:target]).to eq("/path/to/target")
      expect(hash[:path]).to eq("/link")
      expect(hash[:inode]).to eq(12345)
    end
  end

  describe "#to_s" do
    it "returns string representation" do
      link = described_class.new(target: "/target", path: "/link")
      expect(link.to_s).to eq("/link -> /target (hard link)")
    end
  end

  describe "#inspect" do
    it "returns inspect representation" do
      link = described_class.new(
        target: "/target",
        path: "/link",
        inode: 12345,
      )
      expect(link.inspect).to include("HardLink")
      expect(link.inspect).to include("/target")
      expect(link.inspect).to include("/link")
      expect(link.inspect).to include("12345")
    end
  end
end
