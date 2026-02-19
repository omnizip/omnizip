# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Xz do
  describe "XZ Utils reference test files" do
    # Test all good files from XZ Utils test suite
    Dir.glob("spec/fixtures/xz_utils/reference/good*.xz").each do |file|
      basename = File.basename(file)

      it "successfully decodes #{basename}" do
        data = File.binread(file)

        reader = Omnizip::Formats::Xz::Reader.new(StringIO.new(data))
        result = reader.read

        expect(result).not_to be_nil
        expect(result.bytesize).to be >= 0
      end
    end

    # Test all bad files from XZ Utils test suite
    Dir.glob("spec/fixtures/xz_utils/reference/bad*.xz").each do |file|
      basename = File.basename(file)

      it "correctly rejects #{basename} as corrupted" do
        data = File.binread(file)

        # Catch any exception for now
        expect do
          reader = Omnizip::Formats::Xz::Reader.new(StringIO.new(data))
          reader.read
        end.to raise_error(Exception)
      end
    end
  end
end
