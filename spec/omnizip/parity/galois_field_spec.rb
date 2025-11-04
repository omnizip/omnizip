# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/galois_field"

RSpec.describe Omnizip::Parity::GaloisField do
  subject(:gf) { described_class.new(16) }

  describe "#initialize" do
    it "creates GF(2^16)" do
      expect(gf.power).to eq(16)
      expect(gf.size).to eq(65536)
    end

    it "raises error for invalid power" do
      expect {
        described_class.new(8)
      }.to raise_error(ArgumentError, /Only GF\(2\^16\) supported/)
    end
  end

  describe "#multiply" do
    it "multiplies field elements" do
      result = gf.multiply(0x1234, 0x5678)
      expect(result).to be_a(Integer)
      expect(result).to be_between(0, 0xFFFF)
    end

    it "returns zero when multiplying by zero" do
      expect(gf.multiply(0, 0x1234)).to eq(0)
      expect(gf.multiply(0x1234, 0)).to eq(0)
    end

    it "has identity element" do
      expect(gf.multiply(0x1234, 1)).to eq(0x1234)
      expect(gf.multiply(1, 0x5678)).to eq(0x5678)
    end

    it "is commutative" do
      a = 0x1234
      b = 0x5678
      expect(gf.multiply(a, b)).to eq(gf.multiply(b, a))
    end

    it "is associative" do
      a = 0x1234
      b = 0x5678
      c = 0x9ABC
      result1 = gf.multiply(gf.multiply(a, b), c)
      result2 = gf.multiply(a, gf.multiply(b, c))
      expect(result1).to eq(result2)
    end
  end

  describe "#divide" do
    it "divides field elements" do
      a = 0x1234
      b = 0x5678
      quotient = gf.divide(a, b)
      expect(quotient).to be_a(Integer)
      expect(gf.multiply(quotient, b)).to eq(a)
    end

    it "raises error when dividing by zero" do
      expect {
        gf.divide(0x1234, 0)
      }.to raise_error(ZeroDivisionError)
    end

    it "returns zero when zero is dividend" do
      expect(gf.divide(0, 0x1234)).to eq(0)
    end

    it "has identity element" do
      expect(gf.divide(0x1234, 1)).to eq(0x1234)
    end
  end

  describe "#add" do
    it "adds field elements (XOR)" do
      result = gf.add(0x1234, 0x5678)
      expect(result).to eq(0x1234 ^ 0x5678)
    end

    it "has identity element (zero)" do
      expect(gf.add(0x1234, 0)).to eq(0x1234)
      expect(gf.add(0, 0x5678)).to eq(0x5678)
    end

    it "is commutative" do
      a = 0x1234
      b = 0x5678
      expect(gf.add(a, b)).to eq(gf.add(b, a))
    end

    it "is self-inverse (a + a = 0)" do
      expect(gf.add(0x1234, 0x1234)).to eq(0)
    end
  end

  describe "#subtract" do
    it "subtracts field elements (same as add in GF(2^n))" do
      a = 0x1234
      b = 0x5678
      expect(gf.subtract(a, b)).to eq(gf.add(a, b))
    end
  end

  describe "#power" do
    it "raises element to power" do
      base = 0x1234
      expect(gf.power(base, 0)).to eq(1)
      expect(gf.power(base, 1)).to eq(base)
    end

    it "returns zero for zero base" do
      expect(gf.power(0, 5)).to eq(0)
    end

    it "computes correct powers" do
      base = gf.generator
      # alpha^0 = 1
      expect(gf.power(base, 0)).to eq(1)
      # alpha^1 = 2
      expect(gf.power(base, 1)).to eq(2)
      # alpha^2 should be computed correctly
      result = gf.power(base, 2)
      expect(result).to eq(gf.multiply(base, base))
    end
  end

  describe "#inverse" do
    it "finds multiplicative inverse" do
      a = 0x1234
      inv = gf.inverse(a)
      expect(gf.multiply(a, inv)).to eq(1)
    end

    it "raises error for zero" do
      expect {
        gf.inverse(0)
      }.to raise_error(ZeroDivisionError)
    end

    it "inverse of 1 is 1" do
      expect(gf.inverse(1)).to eq(1)
    end
  end

  describe "#generator" do
    it "returns generator element" do
      expect(gf.generator).to eq(2)
    end
  end

  describe "field properties" do
    it "satisfies distributive law" do
      a = 0x1234
      b = 0x5678
      c = 0x9ABC

      # a * (b + c) = (a * b) + (a * c)
      left = gf.multiply(a, gf.add(b, c))
      right = gf.add(gf.multiply(a, b), gf.multiply(a, c))
      expect(left).to eq(right)
    end

    it "has correct field order" do
      # In GF(2^16), alpha^65535 = 1
      alpha = gf.generator
      result = gf.power(alpha, 65535)
      expect(result).to eq(1)
    end
  end
end