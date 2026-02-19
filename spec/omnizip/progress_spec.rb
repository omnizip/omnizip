# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Progress do
  describe ".track" do
    it "creates a progress tracker with default settings" do
      tracker = described_class.track(total_files: 10, total_bytes: 1000)

      expect(tracker).to be_a(Omnizip::Progress::ProgressTracker)
      expect(tracker.operation_progress.total_files).to eq(10)
      expect(tracker.operation_progress.total_bytes).to eq(1000)
    end

    it "supports custom reporter" do
      tracker = described_class.track(
        total_files: 10,
        total_bytes: 1000,
        reporter: :console,
      )

      expect(tracker.reporters).to all(be_a(Omnizip::Progress::ProgressReporter))
    end

    it "supports callback block" do
      callback_called = false
      tracker = described_class.track(
        total_files: 10,
        total_bytes: 1000,
      ) do |_progress|
        callback_called = true
      end

      tracker.update(files: 1, bytes: 100)
      sleep 0.6 # Wait for update interval

      expect(callback_called).to be true
    end
  end

  describe Omnizip::Progress::OperationProgress do
    let(:progress) do
      described_class.new(total_files: 100, total_bytes: 10_000)
    end

    it "initializes with totals" do
      expect(progress.total_files).to eq(100)
      expect(progress.total_bytes).to eq(10_000)
      expect(progress.files_done).to eq(0)
      expect(progress.bytes_done).to eq(0)
    end

    it "updates progress" do
      progress.update(files: 10, bytes: 1000, current_file: "test.txt")

      expect(progress.files_done).to eq(10)
      expect(progress.bytes_done).to eq(1000)
      expect(progress.current_file).to eq("test.txt")
    end

    it "calculates percentage" do
      progress.update(files: 50, bytes: 5000)

      expect(progress.percentage).to eq(50.0)
      expect(progress.files_percent).to eq(50.0)
      expect(progress.bytes_percent).to eq(50.0)
    end

    it "handles zero totals" do
      zero_progress = described_class.new(total_files: 0, total_bytes: 0)

      expect(zero_progress.percentage).to eq(0.0)
      expect(zero_progress.files_percent).to eq(0.0)
    end

    it "calculates remaining counts" do
      progress.update(files: 30, bytes: 3000)

      expect(progress.remaining_files).to eq(70)
      expect(progress.remaining_bytes).to eq(7000)
    end

    it "detects completion" do
      expect(progress.complete?).to be false

      progress.update(files: 100, bytes: 10_000)
      expect(progress.complete?).to be true
    end

    it "tracks elapsed time" do
      expect(progress.elapsed_seconds).to be >= 0
      sleep 0.1
      expect(progress.elapsed_seconds).to be >= 0.1
    end
  end

  describe Omnizip::Progress::ProgressTracker do
    let(:tracker) do
      described_class.new(
        total_files: 100,
        total_bytes: 10_000,
        update_interval: 0.1,
      )
    end

    it "updates progress" do
      tracker.update(files: 10, bytes: 1000, current_file: "test.txt")

      expect(tracker.files_processed).to eq(10)
      expect(tracker.bytes_processed).to eq(1000)
      expect(tracker.current_file).to eq("test.txt")
      expect(tracker.percentage).to eq(10.0)
    end

    it "provides rate information" do
      tracker.update(files: 0, bytes: 0)
      sleep 0.2
      tracker.update(files: 10, bytes: 1000)

      expect(tracker.rate_bps).to be >= 0
      expect(tracker.rate_formatted).to be_a(String)
    end

    it "provides ETA information" do
      tracker.update(files: 0, bytes: 0)
      sleep 0.2
      tracker.update(files: 10, bytes: 1000)

      eta_result = tracker.eta_result
      expect(eta_result).to be_a(Omnizip::Models::ETAResult)
      expect(tracker.eta_formatted).to be_a(String)
    end

    it "is thread-safe" do
      threads = Array.new(10) do |i|
        Thread.new do
          tracker.update(files: i, bytes: i * 100)
        end
      end

      threads.each(&:join)
      expect(tracker.files_processed).to be_between(0, 10)
    end

    it "reports to registered reporters" do
      reported = false
      reporter = Omnizip::Progress::CallbackReporter.new do
        reported = true
      end

      tracker.add_reporter(reporter)
      tracker.update(files: 10, bytes: 1000)
      sleep 0.2 # Wait for update interval

      expect(reported).to be true
    end
  end

  describe Omnizip::Progress::ProgressReporter do
    it "requires subclasses to implement report" do
      reporter = described_class.new
      tracker = Omnizip::Progress::ProgressTracker.new(
        total_files: 10,
        total_bytes: 1000,
      )

      expect do
        reporter.report(tracker)
      end.to raise_error(NotImplementedError)
    end
  end

  describe Omnizip::Progress::SilentReporter do
    it "does nothing when reporting" do
      reporter = described_class.new
      tracker = Omnizip::Progress::ProgressTracker.new(
        total_files: 10,
        total_bytes: 1000,
      )

      expect { reporter.report(tracker) }.not_to raise_error
    end
  end

  describe Omnizip::Progress::CallbackReporter do
    it "calls callback on report" do
      called_with = nil
      reporter = described_class.new do |progress|
        called_with = progress
      end

      tracker = Omnizip::Progress::ProgressTracker.new(
        total_files: 10,
        total_bytes: 1000,
      )

      reporter.report(tracker)
      expect(called_with).to eq(tracker)
    end
  end

  describe Omnizip::Progress::LogReporter do
    let(:log_io) { StringIO.new }
    let(:reporter) { described_class.new(log_file: log_io) }
    let(:tracker) do
      Omnizip::Progress::ProgressTracker.new(
        total_files: 10,
        total_bytes: 1000,
      )
    end

    it "writes progress to log file" do
      tracker.update(files: 5, bytes: 500, current_file: "test.txt")
      reporter.report(tracker)

      log_output = log_io.string
      expect(log_output).to include("Progress:")
      expect(log_output).to include("50.0%")
    end

    it "writes verbose output when enabled" do
      verbose_reporter = described_class.new(log_file: log_io, verbose: true)
      tracker.update(files: 5, bytes: 500, current_file: "test.txt")
      verbose_reporter.report(tracker)

      log_output = log_io.string
      expect(log_output).to include("5/10 files")
      expect(log_output).to include("500/1000 bytes")
    end

    it "writes start message" do
      reporter.start(tracker)
      expect(log_io.string).to include("Started:")
    end

    it "writes finish message" do
      reporter.finish(tracker)
      expect(log_io.string).to include("Completed")
    end
  end

  describe Omnizip::Progress::ProgressBar do
    let(:progress_bar) { described_class.new(width: 80, use_color: false) }
    let(:tracker) do
      Omnizip::Progress::ProgressTracker.new(
        total_files: 100,
        total_bytes: 10_000,
      )
    end

    it "renders progress bar" do
      tracker.update(files: 50, bytes: 5000, current_file: "test.txt")
      output = progress_bar.render(tracker)

      expect(output).to include("[")
      expect(output).to include("]")
      expect(output).to include("50%")
      expect(output).to include("test.txt")
    end

    it "shows file count" do
      tracker.update(files: 25, bytes: 2500)
      output = progress_bar.render(tracker)

      expect(output).to include("(25/100 files)")
    end

    it "clears the bar" do
      clear_str = progress_bar.clear
      expect(clear_str).to start_with("\r")
    end
  end

  describe Omnizip::Progress::ConsoleReporter do
    let(:output) { StringIO.new }
    let(:reporter) { described_class.new(output: output, use_color: false) }
    let(:tracker) do
      Omnizip::Progress::ProgressTracker.new(
        total_files: 10,
        total_bytes: 1000,
      )
    end

    it "does not output when not a TTY" do
      allow(output).to receive(:tty?).and_return(false)
      reporter.report(tracker)

      expect(output.string).to be_empty
    end

    it "finishes cleanly" do
      allow(output).to receive(:tty?).and_return(true)
      reporter.start(tracker)
      tracker.update(files: 5, bytes: 500)
      reporter.report(tracker) # Mark as started
      reporter.finish(tracker)

      expect(output.string).to include("\n")
    end
  end
end
