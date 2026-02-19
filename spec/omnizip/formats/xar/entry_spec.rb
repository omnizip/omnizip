# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Xar::Entry do
  describe "#initialize" do
    it "creates a file entry with defaults" do
      entry = described_class.new("test.txt")

      expect(entry.name).to eq("test.txt")
      expect(entry.type).to eq("file")
      expect(entry.mode).to eq(0o644)
      expect(entry.file?).to be true
    end

    it "creates a directory entry" do
      entry = described_class.new("mydir", type: "directory")

      expect(entry.type).to eq("directory")
      expect(entry.directory?).to be true
    end

    it "creates a symlink entry" do
      entry = described_class.new("link", type: "symlink", link_target: "target.txt")

      expect(entry.symlink?).to be true
      expect(entry.link_target).to eq("target.txt")
    end
  end

  describe "#data=" do
    it "sets data and updates size" do
      entry = described_class.new("test.txt")
      entry.data = "Hello, World!"

      expect(entry.data).to eq("Hello, World!")
      expect(entry.data_size).to eq(13)
      expect(entry.size).to eq(13)
    end
  end

  describe "#file?" do
    it "returns true for regular files" do
      entry = described_class.new("test.txt", type: "file")
      expect(entry.file?).to be true
    end
  end

  describe "#directory?" do
    it "returns true for directories" do
      entry = described_class.new("dir", type: "directory")
      expect(entry.directory?).to be true
    end
  end

  describe "#symlink?" do
    it "returns true for symlinks" do
      entry = described_class.new("link", type: "symlink")
      expect(entry.symlink?).to be true
    end
  end

  describe "#hardlink?" do
    it "returns true for hardlinks" do
      entry = described_class.new("link", type: "hardlink")
      expect(entry.hardlink?).to be true
    end
  end

  describe "#device?" do
    it "returns true for block devices" do
      entry = described_class.new("dev", type: "block")
      expect(entry.device?).to be true
    end

    it "returns true for character devices" do
      entry = described_class.new("dev", type: "character")
      expect(entry.device?).to be true
    end
  end

  describe "#fifo?" do
    it "returns true for FIFOs" do
      entry = described_class.new("fifo", type: "fifo")
      expect(entry.fifo?).to be true
    end
  end

  describe "#socket?" do
    it "returns true for sockets" do
      entry = described_class.new("sock", type: "socket")
      expect(entry.socket?).to be true
    end
  end

  describe ".type_from_mode" do
    it "returns directory for directory mode" do
      expect(described_class.type_from_mode(0o040755)).to eq("directory")
    end

    it "returns file for regular file mode" do
      expect(described_class.type_from_mode(0o100644)).to eq("file")
    end

    it "returns symlink for symlink mode" do
      expect(described_class.type_from_mode(0o120755)).to eq("symlink")
    end
  end

  describe "#to_h" do
    it "converts entry to hash" do
      entry = described_class.new("test.txt",
                                  id: 1,
                                  type: "file",
                                  mode: 0o644,
                                  uid: 1000,
                                  gid: 1000,
                                  size: 100)
      entry.data_offset = 0
      entry.data_length = 50
      entry.data_size = 100

      hash = entry.to_h

      expect(hash[:name]).to eq("test.txt")
      expect(hash[:type]).to eq("file")
      expect(hash[:mode]).to eq("0644")
      expect(hash[:uid]).to eq(1000)
      expect(hash[:gid]).to eq(1000)
      expect(hash[:data][:offset]).to eq(0)
    end
  end

  describe "ExtendedAttribute" do
    it "creates extended attribute" do
      ea = Omnizip::Formats::Xar::Entry::ExtendedAttribute.new(name: "user.comment")

      expect(ea.name).to eq("user.comment")
      expect(ea.data_offset).to eq(0)
    end
  end
end
