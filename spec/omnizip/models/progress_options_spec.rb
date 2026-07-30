# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::ProgressOptions do
  describe "defaults" do
    it "uses the documented default values" do
      options = described_class.new

      expect(options.reporter).to eq("auto")
      expect(options.update_interval).to eq(0.5)
      expect(options.show_rate).to be true
      expect(options.show_eta).to be true
      expect(options.show_files).to be true
      expect(options.show_bytes).to be true
    end
  end

  describe "#to_hash" do
    it "emits every key even when nothing was assigned" do
      expect(described_class.new.to_hash).to eq(
        "reporter" => "auto",
        "update_interval" => 0.5,
        "show_rate" => true,
        "show_eta" => true,
        "show_files" => true,
        "show_bytes" => true,
      )
    end

    it "reflects assigned values" do
      options = described_class.new
      options.reporter = "silent"
      options.show_eta = false

      expect(options.to_hash).to include(
        "reporter" => "silent",
        "show_eta" => false,
      )
    end

    it "drops a key that was explicitly set to nil" do
      options = described_class.new
      options.reporter = nil

      expect(options.to_hash).not_to have_key("reporter")
    end
  end

  describe "JSON round-trip" do
    it "restores every attribute" do
      options = described_class.new
      options.reporter = "bar"
      options.update_interval = 1.5
      options.show_rate = false
      options.show_eta = false
      options.show_files = false
      options.show_bytes = false

      restored = described_class.from_json(options.to_json)

      expect(restored.reporter).to eq("bar")
      expect(restored.update_interval).to eq(1.5)
      expect(restored.show_rate).to be false
      expect(restored.show_eta).to be false
      expect(restored.show_files).to be false
      expect(restored.show_bytes).to be false
    end
  end
end
