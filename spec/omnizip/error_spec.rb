# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Error do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end

  describe "hierarchy" do
    it "has CompressionError" do
      expect(Omnizip::CompressionError).to be < described_class
    end

    it "has DecompressionError" do
      expect(Omnizip::DecompressionError).to be < described_class
    end

    it "has AlgorithmNotFoundError" do
      expect(Omnizip::AlgorithmNotFoundError).to be < described_class
    end

    it "has UnknownChecksumError" do
      expect(Omnizip::UnknownChecksumError).to be < described_class
    end

    it "has UnknownFilterError" do
      expect(Omnizip::UnknownFilterError).to be < described_class
    end

    it "has UnknownEncryptionStrategyError" do
      expect(Omnizip::UnknownEncryptionStrategyError).to be < described_class
    end

    it "has ConversionNotSupportedError" do
      expect(Omnizip::ConversionNotSupportedError).to be < described_class
    end

    it "has UnsupportedFormatError" do
      expect(Omnizip::UnsupportedFormatError).to be < described_class
    end

    it "has OptimizationNotFoundError" do
      expect(Omnizip::OptimizationNotFoundError).to be < described_class
    end
  end

  describe "backward-compat aliases" do
    it "aliases UnknownAlgorithmError to AlgorithmNotFoundError" do
      expect(Omnizip::UnknownAlgorithmError).to equal(Omnizip::AlgorithmNotFoundError)
    end

    it "aliases OptimizationNotFound to OptimizationNotFoundError" do
      expect(Omnizip::OptimizationNotFound).to equal(Omnizip::OptimizationNotFoundError)
    end

    it "aliases IOError to IOOperationError" do
      expect(Omnizip::IOError).to equal(Omnizip::IOOperationError)
    end
  end

  describe Omnizip::NotLicensedError do
    it "provides a default message mentioning WinRAR" do
      err = described_class.new
      expect(err.message).to include("WinRAR")
    end
  end

  describe Omnizip::RarNotAvailableError do
    it "provides a default message with install instructions" do
      err = described_class.new
      expect(err.message).to include("WinRAR executable not found")
    end
  end
end
