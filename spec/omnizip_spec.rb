# frozen_string_literal: true

RSpec.describe Omnizip do
  it "has a version number" do
    expect(Omnizip::VERSION).not_to be_nil
  end

  it "defines the base Error class" do
    expect(Omnizip::Error).to be < StandardError
  end

  it "defines CompressionError" do
    expect(Omnizip::CompressionError).to be < Omnizip::Error
  end

  it "defines FormatError" do
    expect(Omnizip::FormatError).to be < Omnizip::Error
  end

  it "defines IOError" do
    expect(Omnizip::IOError).to be < Omnizip::Error
  end
end
