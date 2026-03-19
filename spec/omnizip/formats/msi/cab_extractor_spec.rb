# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::CabExtractor do
  let(:fixtures_dir) { "spec/fixtures/lessmsi/MsiInput" }
  let(:msi_path) { "#{fixtures_dir}/putty-0.68-installer.msi" }

  let(:ole) { Omnizip::Formats::Ole::Storage.open(msi_path) }
  let(:stream_name_map) do
    map = {}
    ole.root.children.each do |child|
      encoded_name = child.name
      decoded_name = Omnizip::Formats::Msi::Constants.decode_stream_name(encoded_name)
      map[decoded_name] = encoded_name
    end
    map
  end
  let(:stream_reader) do
    lambda do |base_name|
      # Try decoded name from map first
      if stream_name_map.key?(base_name)
        data = begin
          ole.read(stream_name_map[base_name])
        rescue StandardError
          nil
        end
        return data if data && !data.empty?
      end

      # Try various encodings
      utf16le = base_name.encode("UTF-16LE")
      [1, 5].each do |prefix|
        encoded = prefix.chr.b.to_s.b << utf16le.b
        data = begin
          ole.read(encoded)
        rescue StandardError
          nil
        end
        return data if data && !data.empty?
      end

      begin
        ole.read(base_name)
      rescue StandardError
        nil
      end
    end
  end
  let(:string_pool) { Omnizip::Formats::Msi::StringPool.new(ole, stream_reader) }
  let(:table_parser) { Omnizip::Formats::Msi::TableParser.new(string_pool, stream_reader) }
  let(:media_table) { table_parser.table("Media") }
  let(:extractor) do
    described_class.new(ole, media_table, msi_path, stream_reader)
  end

  after do
    ole.close
  end

  describe "#initialize" do
    it "stores OLE and media table" do
      expect(extractor.ole).to eq(ole)
      expect(extractor.media_table).to eq(media_table)
    end
  end

  describe "#get_cabinet_data" do
    it "returns nil for nil cabinet name" do
      expect(extractor.get_cabinet_data(nil)).to be_nil
    end

    it "returns nil for empty cabinet name" do
      expect(extractor.get_cabinet_data("")).to be_nil
    end

    it "extracts embedded cabinet data" do
      # PuTTY MSI has embedded cabinet
      cab_name = media_table.first["Cabinet"]

      skip "No embedded cabinet in this MSI" unless cab_name&.start_with?("#")

      data = extractor.get_cabinet_data(cab_name)
      expect(data).to be_a(String)
      expect(data.bytesize).to be > 0

      # Check CAB signature (MSCF)
      expect(data[0, 4]).to eq("MSCF")
    end
  end

  describe "#extract_cabinets" do
    it "extracts cabinets to temp files" do
      cabinets = extractor.extract_cabinets

      begin
        expect(cabinets).to be_a(Hash)
        expect(cabinets.size).to be > 0

        cabinets.each_value do |cab_info|
          expect(cab_info[:path]).to be_a(String)
          expect(cab_info[:name]).to be_a(String)
          expect(cab_info[:last_sequence]).to be_an(Integer)
          expect(File.exist?(cab_info[:path])).to be true
        end
      ensure
        # Clean up
        cabinets.each_value do |cab_info|
          cab_info[:temp_file]&.close!
        rescue StandardError
          nil
        end
      end
    end
  end

  describe "#find_cabinet_for_sequence" do
    it "finds cabinet containing file by sequence" do
      cabinets = extractor.extract_cabinets

      begin
        # Find cabinet for sequence 1
        cab = extractor.find_cabinet_for_sequence(1, cabinets)
        expect(cab).to be_a(Hash)
        expect(cab[:last_sequence]).to be >= 1
      ensure
        cabinets.each_value do |cab_info|
          cab_info[:temp_file]&.close!
        rescue StandardError
          nil
        end
      end
    end
  end
end
