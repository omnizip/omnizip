# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::StringPool do
  let(:fixtures_dir) { "spec/fixtures/lessmsi/MsiInput" }

  describe "#initialize" do
    it "loads string pool from putty MSI" do
      msi_path = "#{fixtures_dir}/putty-0.68-installer.msi"

      ole = Omnizip::Formats::Ole::Storage.open(msi_path)
      pool = described_class.new(ole)
      ole.close

      expect(pool.strings).to be_an(Array)
      expect(pool.strings.size).to be > 0
    end

    it "decodes UTF-16LE strings correctly" do
      msi_path = "#{fixtures_dir}/putty-0.68-installer.msi"

      ole = Omnizip::Formats::Ole::Storage.open(msi_path)
      pool = described_class.new(ole)
      ole.close

      # Check that strings are valid UTF-8
      pool.strings.each do |str|
        expect(str.encoding).to eq(Encoding::UTF_8)
      end
    end
  end

  describe "#[]" do
    it "returns string by index" do
      msi_path = "#{fixtures_dir}/putty-0.68-installer.msi"

      ole = Omnizip::Formats::Ole::Storage.open(msi_path)
      pool = described_class.new(ole)
      ole.close

      # First string should be accessible
      expect(pool[1]).to be_a(String)
    end

    it "returns nil for invalid index" do
      msi_path = "#{fixtures_dir}/putty-0.68-installer.msi"

      ole = Omnizip::Formats::Ole::Storage.open(msi_path)
      pool = described_class.new(ole)
      ole.close

      expect(pool[0]).to be_nil
      expect(pool[-1]).to be_nil
      expect(pool[nil]).to be_nil
    end
  end
end
