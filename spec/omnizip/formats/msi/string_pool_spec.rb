# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::StringPool do
  let(:fixtures_dir) { "spec/fixtures/lessmsi/MsiInput" }
  let(:msi_path) { "#{fixtures_dir}/putty-0.68-installer.msi" }

  describe "#initialize" do
    it "loads string pool from putty MSI" do
      reader = Omnizip::Formats::Msi::Reader.new(msi_path)
      reader.open
      pool = reader.string_pool
      reader.close

      expect(pool.strings).to be_an(Array)
      expect(pool.strings.size).to be > 0
      expect(pool.strings[1]).to be_a(String)
    end
  end

  describe "#[]" do
    it "returns string by index" do
      reader = Omnizip::Formats::Msi::Reader.new(msi_path)
      reader.open
      pool = reader.string_pool
      reader.close

      expect(pool[0]).to be_nil
      expect(pool[-1]).to be_nil
      expect(pool[nil]).to be_nil
    end
  end
end
