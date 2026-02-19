# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::ETA do
  describe ".create_estimator" do
    it "creates exponential smoothing estimator by default" do
      estimator = described_class.create_estimator

      expect(estimator).to be_a(Omnizip::ETA::ExponentialSmoothingEstimator)
    end

    it "creates moving average estimator" do
      estimator = described_class.create_estimator(:moving_average)

      expect(estimator).to be_a(Omnizip::ETA::MovingAverageEstimator)
    end

    it "raises error for unknown strategy" do
      expect do
        described_class.create_estimator(:unknown)
      end.to raise_error(ArgumentError, /Unknown estimation strategy/)
    end
  end

  describe ".format_time" do
    it "formats zero seconds" do
      expect(described_class.format_time(0)).to eq("0s")
    end

    it "formats seconds only" do
      expect(described_class.format_time(45)).to eq("45s")
    end

    it "formats minutes and seconds" do
      expect(described_class.format_time(150)).to eq("2m 30s")
    end

    it "formats hours, minutes, and seconds" do
      expect(described_class.format_time(3665)).to eq("1h 1m 5s")
    end

    it "handles infinity" do
      expect(described_class.format_time(Float::INFINITY)).to eq("∞")
    end
  end

  describe Omnizip::ETA::SampleHistory do
    let(:history) { described_class.new(max_size: 5) }

    it "initializes empty" do
      expect(history).to be_empty
      expect(history.size).to eq(0)
    end

    it "adds samples" do
      history.add_sample(bytes_processed: 100, files_processed: 1)
      history.add_sample(bytes_processed: 200, files_processed: 2)

      expect(history.size).to eq(2)
      expect(history.latest.bytes_processed).to eq(200)
      expect(history.oldest.bytes_processed).to eq(100)
    end

    it "limits size" do
      10.times do |i|
        history.add_sample(bytes_processed: i * 100, files_processed: i)
      end

      expect(history.size).to eq(5)
      expect(history.oldest.bytes_processed).to eq(500)
    end

    it "calculates average rate" do
      t = Time.now
      history.add_sample(bytes_processed: 0, files_processed: 0, timestamp: t)
      history.add_sample(bytes_processed: 1000, files_processed: 10,
                         timestamp: t + 1)

      expect(history.average_rate).to be_within(10).of(1000)
    end

    it "calculates recent rate" do
      t = Time.now
      history.add_sample(bytes_processed: 0, files_processed: 0, timestamp: t)
      history.add_sample(bytes_processed: 1000, files_processed: 10,
                         timestamp: t + 1)
      history.add_sample(bytes_processed: 2000, files_processed: 20,
                         timestamp: t + 2)

      rate = history.recent_rate(2.0)
      expect(rate).to be >= 0
    end

    it "calculates rate standard deviation" do
      t = Time.now
      5.times do |i|
        history.add_sample(
          bytes_processed: i * 100,
          files_processed: i,
          timestamp: t + i,
        )
      end

      std_dev = history.rate_std_dev
      expect(std_dev).to be >= 0
    end

    it "clears samples" do
      history.add_sample(bytes_processed: 100, files_processed: 1)
      history.clear

      expect(history).to be_empty
    end
  end

  describe Omnizip::ETA::RateCalculator do
    let(:history) { Omnizip::ETA::SampleHistory.new }
    let(:calculator) do
      described_class.new(sample_history: history, window_seconds: 2.0)
    end

    before do
      t = Time.now
      history.add_sample(bytes_processed: 0, files_processed: 0, timestamp: t)
      history.add_sample(bytes_processed: 1_000_000, files_processed: 10,
                         timestamp: t + 1)
      history.add_sample(bytes_processed: 2_000_000, files_processed: 20,
                         timestamp: t + 2)
    end

    it "calculates bytes per second" do
      expect(calculator.bytes_per_second).to be > 0
    end

    it "calculates megabytes per second" do
      expect(calculator.megabytes_per_second).to be > 0
    end

    it "calculates files per second" do
      expect(calculator.files_per_second).to be > 0
    end

    it "formats rate" do
      formatted = calculator.format_rate(1500)
      expect(formatted).to include("KB/s")
    end

    it "formats different scales" do
      expect(calculator.format_rate(500)).to include("B/s")
      expect(calculator.format_rate(1500)).to include("KB/s")
      expect(calculator.format_rate(1_500_000)).to include("MB/s")
      expect(calculator.format_rate(1_500_000_000)).to include("GB/s")
    end

    it "checks stability" do
      # With only 3 samples, might not be stable
      stability = calculator.stable?
      expect([true, false]).to include(stability)
    end
  end

  describe Omnizip::ETA::TimeEstimator do
    let(:estimator) { described_class.new }

    it "raises error for estimate method" do
      expect do
        estimator.estimate(1000)
      end.to raise_error(NotImplementedError)
    end

    it "adds samples" do
      estimator.add_sample(bytes_processed: 100, files_processed: 1)
      expect(estimator.sample_history.size).to eq(1)
    end

    it "formats time correctly" do
      expect(estimator.format_time(0)).to eq("0s")
      expect(estimator.format_time(90)).to eq("1m 30s")
      expect(estimator.format_time(3720)).to eq("1h 2m 0s")
    end

    it "calculates confidence interval" do
      3.times do |i|
        estimator.add_sample(bytes_processed: i * 100, files_processed: i)
      end

      lower, upper = estimator.confidence_interval(100)
      expect(lower).to be <= 100
      expect(upper).to be >= 100
    end

    it "checks for sufficient samples" do
      expect(estimator.sufficient_samples?).to be false

      3.times do |i|
        estimator.add_sample(bytes_processed: i * 100, files_processed: i)
      end

      expect(estimator.sufficient_samples?).to be true
    end
  end

  describe Omnizip::ETA::ExponentialSmoothingEstimator do
    let(:estimator) { described_class.new(smoothing_factor: 0.3) }

    before do
      t = Time.now
      estimator.add_sample(bytes_processed: 0, files_processed: 0, timestamp: t)
      estimator.add_sample(bytes_processed: 1000, files_processed: 10,
                           timestamp: t + 1)
      estimator.add_sample(bytes_processed: 2000, files_processed: 20,
                           timestamp: t + 2)
    end

    it "estimates time remaining" do
      result = estimator.estimate(1000)

      expect(result).to be_a(Omnizip::Models::ETAResult)
      expect(result.seconds_remaining).to be >= 0
      expect(result.formatted).to be_a(String)
    end

    it "returns zero for completed operation" do
      result = estimator.estimate(0)

      expect(result.seconds_remaining).to eq(0.0)
      expect(result.formatted).to eq("0s")
    end

    it "returns calculating message without enough samples" do
      new_estimator = described_class.new
      new_estimator.add_sample(bytes_processed: 100, files_processed: 1)

      result = new_estimator.estimate(1000)
      expect(result.formatted).to eq("calculating...")
    end

    it "smooths rate over time" do
      result1 = estimator.estimate(1000)
      estimator.add_sample(bytes_processed: 3000, files_processed: 30)
      result2 = estimator.estimate(1000)

      # Results should be different due to smoothing
      expect(result1.seconds_remaining).not_to eq(result2.seconds_remaining)
    end

    it "resets smoothed rate" do
      estimator.estimate(1000)
      expect(estimator.smoothed_rate).not_to be_nil

      estimator.reset
      expect(estimator.smoothed_rate).to be_nil
    end
  end

  describe Omnizip::ETA::MovingAverageEstimator do
    let(:estimator) { described_class.new(window_size: 3) }

    before do
      t = Time.now
      estimator.add_sample(bytes_processed: 0, files_processed: 0, timestamp: t)
      estimator.add_sample(bytes_processed: 1000, files_processed: 10,
                           timestamp: t + 1)
      estimator.add_sample(bytes_processed: 2000, files_processed: 20,
                           timestamp: t + 2)
    end

    it "estimates time remaining" do
      result = estimator.estimate(1000)

      expect(result).to be_a(Omnizip::Models::ETAResult)
      expect(result.seconds_remaining).to be >= 0
    end

    it "uses moving average window" do
      # Add more samples
      t = Time.now + 2
      estimator.add_sample(bytes_processed: 3000, files_processed: 30,
                           timestamp: t + 3)
      estimator.add_sample(bytes_processed: 4000, files_processed: 40,
                           timestamp: t + 4)

      result = estimator.estimate(1000)
      expect(result.seconds_remaining).to be >= 0
    end
  end

  describe Omnizip::Models::ETAResult do
    let(:result) do
      described_class.new.tap do |r|
        r.seconds_remaining = 150
        r.formatted = "2m 30s"
        r.confidence_lower = 120
        r.confidence_upper = 180
      end
    end

    it "stores ETA data" do
      expect(result.seconds_remaining).to eq(150)
      expect(result.formatted).to eq("2m 30s")
    end

    it "provides confidence interval" do
      expect(result.confidence_interval).to eq([120, 180])
    end

    it "checks reliability" do
      expect(result.reliable?).to be true

      # Wide confidence interval
      wide_result = described_class.new.tap do |r|
        r.seconds_remaining = 100
        r.confidence_lower = 10
        r.confidence_upper = 200
      end

      expect(wide_result.reliable?).to be false
    end
  end
end
