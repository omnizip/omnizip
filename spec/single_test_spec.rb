# frozen_string_literal: true

require "spec_helper"

RSpec.describe "good-1-lzma2-2 test" do
  it "decodes good-1-lzma2-2.xz" do
    file = "spec/fixtures/xz_utils/good/good-1-lzma2-2.xz"
    data = File.binread(file)
    result = Omnizip::Formats::Xz.decode(data)

    expect(result).to be_a(String),
                      "Expected good-1-lzma2-2.xz to decode to a String"
    expect(result.bytesize).to eq(457),
                               "Expected 457 bytes, got #{result.bytesize}"
  end
end
