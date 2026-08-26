# frozen_string_literal: true

require "spec_helper"
require "omnizip/models/attribute_apply"

RSpec.describe Omnizip::Models::AttributeApply do
  it "applies declared attributes from a symbol-keyed hash" do
    options = Omnizip::Models::CompressionOptions.new.apply(
      { level: 7, dictionary_size: 1 << 20 },
    )

    expect(options.level).to eq(7)
    expect(options.dictionary_size).to eq(1 << 20)
  end

  it "ignores unknown and string keys" do
    options = Omnizip::Models::CompressionOptions.new.apply(
      { level: 3, bogus: 1, "level" => 9 },
    )

    expect(options.level).to eq(3)
  end

  it "returns self for chaining" do
    options = Omnizip::Models::CompressionOptions.new

    expect(options.apply({ level: 1 })).to be(options)
  end

  it "is included by every lutaml options model" do
    [Omnizip::Models::CompressionOptions,
     Omnizip::Models::AlgorithmMetadata,
     Omnizip::Models::ParallelOptions].each do |klass|
      expect(klass.ancestors).to include(described_class)
    end
  end
end
