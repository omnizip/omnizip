# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/galois16"

RSpec.describe Omnizip::Parity::Galois16 do
  describe ".build_tables" do
    it "builds log and antilog tables" do
      # Tables should be built automatically during class load
      expect(described_class.instance_variable_get(:@log_table)).not_to be_nil
      expect(described_class.instance_variable_get(:@antilog_table)).not_to be_nil
    end

    it "has correct table sizes" do
      log_table = described_class.instance_variable_get(:@log_table)
      antilog_table = described_class.instance_variable_get(:@antilog_table)

      expect(log_table.size).to eq(65536)
      expect(antilog_table.size).to eq(65536)
    end

    it "maintains log/antilog inverse relationship" do
      # For any non-zero value, antilog[log[x]] == x
      [1, 2, 10, 100, 1000, 10000, 65534, 65535].each do |value|
        log_val = described_class.log(value)
        antilog_val = described_class.antilog(log_val)
        expect(antilog_val).to eq(value), "antilog[log[#{value}]] != #{value}"
      end
    end

    it "handles zero correctly" do
      # log[0] should be LIMIT (65535)
      expect(described_class.log(0)).to eq(65535)
      # antilog[LIMIT] should be 0
      expect(described_class.antilog(65535)).to eq(0)
    end
  end

  describe ".add" do
    it "performs XOR addition" do
      expect(described_class.add(5, 3)).to eq(6) # 0101 ^ 0011 = 0110
      expect(described_class.add(0xFF, 0xFF)).to eq(0)
      expect(described_class.add(0, 42)).to eq(42)
    end

    it "is commutative" do
      a = 1234
      b = 5678
      expect(described_class.add(a, b)).to eq(described_class.add(b, a))
    end

    it "satisfies a + a = 0" do
      [1, 10, 100, 1000, 65535].each do |value|
        expect(described_class.add(value, value)).to eq(0)
      end
    end

    it "masks to 16 bits" do
      expect(described_class.add(0x1FFFF, 0)).to eq(0xFFFF)
    end
  end

  describe ".subtract" do
    it "is same as add (XOR)" do
      a = 1234
      b = 5678
      expect(described_class.subtract(a, b)).to eq(described_class.add(a, b))
    end
  end

  describe ".multiply" do
    it "multiplies in GF(2^16)" do
      # Identity: a * 1 = a
      expect(described_class.multiply(42, 1)).to eq(42)
      expect(described_class.multiply(65535, 1)).to eq(65535)

      # Zero: a * 0 = 0
      expect(described_class.multiply(42, 0)).to eq(0)
      expect(described_class.multiply(0, 42)).to eq(0)
    end

    it "is commutative" do
      a = 123
      b = 456
      expect(described_class.multiply(a,
                                      b)).to eq(described_class.multiply(b, a))
    end

    it "uses log tables for multiplication" do
      a = 100
      b = 200
      log_a = described_class.log(a)
      log_b = described_class.log(b)
      expected = described_class.antilog((log_a + log_b) % 65535)

      expect(described_class.multiply(a, b)).to eq(expected)
    end

    it "handles known values correctly" do
      #  Test some known multiplications
      expect(described_class.multiply(2, 2)).to eq(4)
      expect(described_class.multiply(2, 3)).to eq(6)
    end

    it "masks to 16 bits" do
      result = described_class.multiply(0x10001, 2)
      expect(result).to be <= 0xFFFF
    end
  end

  describe ".divide" do
    it "divides in GF(2^16)" do
      # Identity: a / 1 = a
      expect(described_class.divide(42, 1)).to eq(42)

      # Zero numerator: 0 / a = 0
      expect(described_class.divide(0, 42)).to eq(0)
    end

    it "raises error for division by zero" do
      expect do
        described_class.divide(42,
                               0)
      end.to raise_error(ArgumentError, /Division by zero/)
    end

    it "satisfies (a * b) / b = a" do
      a = 123
      b = 456
      product = described_class.multiply(a, b)
      expect(described_class.divide(product, b)).to eq(a)
    end

    it "satisfies a / a = 1 for non-zero a" do
      [1, 10, 100, 1000, 65534].each do |value|
        expect(described_class.divide(value, value)).to eq(1)
      end
    end
  end

  describe ".power" do
    it "computes a^0 = 1" do
      expect(described_class.power(0, 0)).to eq(1)
      expect(described_class.power(42, 0)).to eq(1)
      expect(described_class.power(65535, 0)).to eq(1)
    end

    it "computes a^1 = a" do
      [1, 42, 100, 65535].each do |value|
        expect(described_class.power(value, 1)).to eq(value)
      end
    end

    it "computes 0^n = 0 for n > 0" do
      expect(described_class.power(0, 1)).to eq(0)
      expect(described_class.power(0, 10)).to eq(0)
    end

    it "computes powers correctly" do
      # 2^2 = 4
      expect(described_class.power(2, 2)).to eq(4)

      # 2^3 = 8
      expect(described_class.power(2, 3)).to eq(8)

      # Use multiply to verify: a^3 = a * a * a
      a = 17
      a_squared = described_class.multiply(a, a)
      a_cubed = described_class.multiply(a_squared, a)
      expect(described_class.power(a, 3)).to eq(a_cubed)
    end

    it "handles large exponents" do
      # Should use log/antilog efficiently
      result = described_class.power(7, 1000)
      expect(result).to be_between(0, 65535)
    end
  end

  describe ".gcd" do
    it "computes greatest common divisor" do
      expect(described_class.gcd(12, 8)).to eq(4)
      expect(described_class.gcd(17, 13)).to eq(1) # coprime
      expect(described_class.gcd(100, 50)).to eq(50)
    end

    it "handles zero" do
      expect(described_class.gcd(0, 5)).to eq(5)
      expect(described_class.gcd(5, 0)).to eq(5)
      expect(described_class.gcd(0, 0)).to eq(0)
    end

    it "is commutative" do
      expect(described_class.gcd(12, 8)).to eq(described_class.gcd(8, 12))
    end
  end

  describe ".select_bases" do
    it "selects correct number of bases" do
      bases = described_class.select_bases(10)
      expect(bases.size).to eq(10)
    end

    it "returns all distinct values" do
      bases = described_class.select_bases(100)
      expect(bases.uniq.size).to eq(100)
    end

    it "returns consistent values" do
      # Should return same bases each time
      bases1 = described_class.select_bases(20)
      bases2 = described_class.select_bases(20)
      expect(bases1).to eq(bases2)
    end
  end

  describe "field properties" do
    it "has additive identity (0)" do
      [1, 42, 65535].each do |a|
        expect(described_class.add(a, 0)).to eq(a)
      end
    end

    it "has multiplicative identity (1)" do
      [2, 42, 65535].each do |a|
        expect(described_class.multiply(a, 1)).to eq(a)
      end
    end

    it "has additive inverse (self)" do
      # In GF(2^n), -a = a
      [1, 42, 65535].each do |a|
        expect(described_class.add(a, a)).to eq(0)
      end
    end

    it "has multiplicative inverse" do
      # For non-zero a, exists b where a * b = 1
      [2, 17, 100].each do |a|
        # b = 1 / a
        b = described_class.divide(1, a)
        product = described_class.multiply(a, b)
        expect(product).to eq(1)
      end
    end

    it "satisfies distributive law: a * (b + c) = a*b + a*c" do
      a = 7
      b = 13
      c = 19

      left = described_class.multiply(a, described_class.add(b, c))
      right = described_class.add(
        described_class.multiply(a, b),
        described_class.multiply(a, c),
      )

      expect(left).to eq(right)
    end
  end

  describe "PAR2 compatibility" do
    it "uses correct generator polynomial" do
      expect(described_class::GENERATOR).to eq(0x1100B)
    end

    it "has correct field size" do
      expect(described_class::FIELD_SIZE).to eq(65536)
      expect(described_class::LIMIT).to eq(65535)
    end

    it "produces base values matching par2cmdline pattern" do
      # The first few bases should follow the pattern from par2cmdline
      bases = described_class.select_bases(10)

      # Verify they're in increasing log order
      logs = bases.map { |b| described_class.log(b) }
      previous_log = -1
      logs.each do |log|
        expect(log).to be > previous_log
        previous_log = log
      end
    end
  end

  describe "edge cases" do
    it "handles maximum value" do
      max = 65535
      expect(described_class.add(max, 0)).to eq(max)
      expect(described_class.multiply(max, 1)).to eq(max)
    end

    it "handles minimum non-zero value" do
      min = 1
      expect(described_class.add(min, 0)).to eq(min)
      expect(described_class.multiply(min, 1)).to eq(min)
      expect(described_class.power(min, 100)).to eq(min)
    end

    it "handles values outside 16-bit range" do
      # Should mask to 16 bits
      expect(described_class.add(0x1FFFF, 0)).to eq(0xFFFF)
      expect(described_class.multiply(0x10001, 1)).to eq(1)
    end
  end
end
