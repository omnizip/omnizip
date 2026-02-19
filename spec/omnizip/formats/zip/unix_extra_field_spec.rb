# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Zip::UnixExtraField do
  describe "#initialize" do
    it "creates field with default version" do
      field = described_class.new
      expect(field.version).to eq(1)
    end

    it "creates field with uid and gid" do
      field = described_class.new(uid: 1000, gid: 1000)
      expect(field.uid).to eq(1000)
      expect(field.gid).to eq(1000)
    end

    it "creates field with link target" do
      field = described_class.new(link_target: "/path/to/target")
      expect(field.link_target).to eq("/path/to/target")
    end
  end

  describe "#symlink?" do
    it "returns true when link_target is present" do
      field = described_class.new(link_target: "/target")
      expect(field.symlink?).to be true
    end

    it "returns false when link_target is nil" do
      field = described_class.new
      expect(field.symlink?).to be false
    end

    it "returns false when link_target is empty" do
      field = described_class.new(link_target: "")
      expect(field.symlink?).to be false
    end
  end

  describe "#to_binary" do
    it "serializes field with uid and gid" do
      field = described_class.new(uid: 1000, gid: 1000)
      binary = field.to_binary

      expect(binary).to be_a(String)
      expect(binary.bytesize).to be > 4 # Tag + size + data
    end

    it "serializes field with link target" do
      field = described_class.new(link_target: "/path/to/target")
      binary = field.to_binary

      expect(binary).to include("/path/to/target")
    end

    it "includes correct tag" do
      field = described_class.new
      binary = field.to_binary
      tag = binary[0, 2].unpack1("v")

      expect(tag).to eq(0x7875)
    end
  end

  describe ".from_binary" do
    it "parses field with uid and gid" do
      original = described_class.new(uid: 1000, gid: 1000)
      binary = original.to_binary[4..] # Skip tag and size
      parsed = described_class.from_binary(binary)

      expect(parsed.uid).to eq(1000)
      expect(parsed.gid).to eq(1000)
    end

    it "parses field with link target" do
      original = described_class.new(
        uid: 1000,
        gid: 1000,
        link_target: "/path/to/target",
      )
      binary = original.to_binary[4..] # Skip tag and size
      parsed = described_class.from_binary(binary)

      expect(parsed.uid).to eq(1000)
      expect(parsed.gid).to eq(1000)
      expect(parsed.link_target).to eq("/path/to/target")
    end

    it "returns nil for nil data" do
      expect(described_class.from_binary(nil)).to be_nil
    end

    it "returns nil for empty data" do
      expect(described_class.from_binary("")).to be_nil
    end
  end

  describe ".find_in_extra_field" do
    it "finds Unix extra field in extra field data" do
      field = described_class.new(uid: 1000, gid: 1000)
      extra_field_data = field.to_binary

      found = described_class.find_in_extra_field(extra_field_data)
      expect(found).not_to be_nil
      expect(found.uid).to eq(1000)
      expect(found.gid).to eq(1000)
    end

    it "finds Unix extra field among multiple fields" do
      # Create a Unix extra field
      unix_field = described_class.new(link_target: "/target")
      unix_binary = unix_field.to_binary

      # Add another field before it
      other_field = [0x0001, 4, 0, 0].pack("vvVV")
      extra_field_data = other_field + unix_binary

      found = described_class.find_in_extra_field(extra_field_data)
      expect(found).not_to be_nil
      expect(found.link_target).to eq("/target")
    end

    it "returns nil when field not found" do
      other_field = [0x0001, 4, 0, 0].pack("vvVV")
      found = described_class.find_in_extra_field(other_field)
      expect(found).to be_nil
    end

    it "returns nil for nil data" do
      expect(described_class.find_in_extra_field(nil)).to be_nil
    end

    it "returns nil for empty data" do
      expect(described_class.find_in_extra_field("")).to be_nil
    end
  end

  describe ".for_symlink" do
    it "creates field for symlink with target" do
      field = described_class.for_symlink("/path/to/target")

      expect(field.link_target).to eq("/path/to/target")
      expect(field.symlink?).to be true
    end

    it "creates field for symlink with uid and gid" do
      field = described_class.for_symlink("/target", uid: 1000, gid: 1000)

      expect(field.link_target).to eq("/target")
      expect(field.uid).to eq(1000)
      expect(field.gid).to eq(1000)
    end
  end

  describe ".for_hardlink" do
    it "creates field for hardlink without target" do
      field = described_class.for_hardlink

      expect(field.link_target).to be_nil
      expect(field.symlink?).to be false
    end

    it "creates field for hardlink with uid and gid" do
      field = described_class.for_hardlink(uid: 1000, gid: 1000)

      expect(field.uid).to eq(1000)
      expect(field.gid).to eq(1000)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      field = described_class.new(
        uid: 1000,
        gid: 1000,
        link_target: "/target",
      )
      hash = field.to_h

      expect(hash[:tag]).to eq(0x7875)
      expect(hash[:version]).to eq(1)
      expect(hash[:uid]).to eq(1000)
      expect(hash[:gid]).to eq(1000)
      expect(hash[:link_target]).to eq("/target")
    end
  end

  describe "round-trip serialization" do
    it "preserves all data through serialization" do
      original = described_class.new(
        uid: 1000,
        gid: 1000,
        link_target: "/path/to/target",
      )

      binary = original.to_binary
      parsed = described_class.find_in_extra_field(binary)

      expect(parsed.uid).to eq(original.uid)
      expect(parsed.gid).to eq(original.gid)
      expect(parsed.link_target).to eq(original.link_target)
    end
  end
end
