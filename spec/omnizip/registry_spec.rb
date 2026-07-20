# frozen_string_literal: true

require "spec_helper"
require "omnizip/registry"

RSpec.describe Omnizip::Registry do
  subject(:registry) { described_class }

  let(:test_error) do
    Class.new(StandardError) do
      def self.name
        "TestNotFoundError"
      end
    end
  end

  let(:subclass) do
    error = test_error
    Class.new(described_class) do
      singleton_class.define_method(:not_found_error_class) { error }
      singleton_class.define_method(:label) { "Widget" }
    end
  end

  around do |example|
    saved = subclass.entries
    subclass.reset!
    example.run
  ensure
    subclass.reset!
    saved.each { |k, v| subclass.register(k, v) }
  end

  describe ".register / .get" do
    it "stores and retrieves a value by Symbol key" do
      value = Object.new
      subclass.register(:alpha, value)
      expect(subclass.get(:alpha)).to be(value)
    end

    it "normalizes String keys to Symbols" do
      value = Object.new
      subclass.register("alpha", value)
      expect(subclass.get(:alpha)).to be(value)
    end

    it "raises the configured not-found error on miss" do
      expect { subclass.get(:missing) }.to raise_error(test_error, /Widget/)
    end

    it "includes available keys in the error message" do
      subclass.register(:one, 1)
      expect { subclass.get(:missing) }.to raise_error(/Available: one/)
    end
  end

  describe ".registered?" do
    it "returns true for registered keys" do
      subclass.register(:alpha, 1)
      expect(subclass.registered?(:alpha)).to be true
    end

    it "returns false for unknown keys" do
      expect(subclass.registered?(:missing)).to be false
    end
  end

  describe ".available" do
    it "lists registered keys" do
      subclass.register(:a, 1)
      subclass.register(:b, 2)
      expect(subclass.available).to contain_exactly(:a, :b)
    end

    it "is aliased as .all" do
      subclass.register(:a, 1)
      expect(subclass.all).to eq(subclass.available)
    end
  end

  describe ".reset!" do
    it "clears the registry" do
      subclass.register(:a, 1)
      subclass.reset!
      expect(subclass.available).to be_empty
    end

    it "is aliased as .clear and .reset" do
      expect(subclass.method(:reset!)).to eq(subclass.method(:clear))
      expect(subclass.method(:reset!)).to eq(subclass.method(:reset))
    end
  end

  describe ".entries" do
    it "returns a defensive copy" do
      subclass.register(:a, 1)
      copy = subclass.entries
      copy[:a] = 999
      expect(subclass.get(:a)).to eq(1)
    end
  end

  describe "thread safety" do
    it "serializes concurrent registrations without losing entries" do
      threads = Array.new(20) do |i|
        Thread.new { subclass.register(:"key_#{i}", i) }
      end
      threads.each(&:join)
      expect(subclass.available.size).to eq(20)
    end
  end

  describe ".normalize_key" do
    it "uses Symbols by default" do
      expect(described_class.normalize_key("foo")).to eq(:foo)
      expect(described_class.normalize_key(:foo)).to eq(:foo)
    end
  end

  describe ".label" do
    it "strips the Omnizip:: prefix from the class name" do
      expect(described_class.label).to eq("Registry")
    end
  end
end
