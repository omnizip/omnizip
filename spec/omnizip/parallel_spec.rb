# frozen_string_literal: true

require "spec_helper"
require "omnizip/parallel"
require "fractor"
require "fileutils"
require "tmpdir"

# Trivial worker used to exercise the pool without archive I/O
class ParallelSpecDoublingWorker < Fractor::Worker
  def process(work)
    Fractor::WorkResult.new(result: work.input[:value] * 2, work: work)
  end
end

RSpec.describe Omnizip::Parallel do
  let(:tmpdir) { Dir.mktmpdir("omnizip_parallel") }

  after { FileUtils.rm_rf(tmpdir) }

  describe ".extract_archive" do
    it "extracts every entry through the native reader" do
      src_dir = File.join(tmpdir, "src")
      FileUtils.mkdir_p(File.join(src_dir, "nested"))
      File.binwrite(File.join(src_dir, "a.txt"), "alpha " * 500)
      File.binwrite(File.join(src_dir, "nested", "b.bin"), "\x00\xFF".b * 300)
      File.binwrite(File.join(src_dir, "c.md"), "# doc\n" * 100)

      archive = File.join(tmpdir, "parallel.zip")
      Omnizip.compress_directory(src_dir, archive)

      dest = File.join(tmpdir, "out")
      paths = described_class.extract_archive(archive, dest, threads: 3)

      # 3 files plus the nested/ directory entry
      expect(paths.size).to eq(4)
      expect(File.directory?(File.join(dest, "nested"))).to be true
      expect(File.binread(File.join(dest, "a.txt"))).to eq("alpha " * 500)
      expect(File.binread(File.join(dest, "nested", "b.bin")))
        .to eq("\x00\xFF".b * 300)
      expect(File.binread(File.join(dest, "c.md"))).to eq("# doc\n" * 100)
    end

    it "reports extraction statistics" do
      src = File.join(tmpdir, "one.txt")
      File.binwrite(src, "stat bytes " * 50)
      archive = File.join(tmpdir, "stats.zip")
      Omnizip.compress_file(src, archive)

      extractor = Omnizip::Parallel::ParallelExtractor.new(threads: 2)
      extractor.extract(archive, File.join(tmpdir, "stats-out"))

      stats = extractor.statistics
      expect(stats[:files_extracted]).to eq(1)
      expect(stats[:bytes_extracted]).to eq(("stat bytes " * 50).bytesize)
      expect(stats[:duration]).to be >= 0
    end

    it "refuses to overwrite without :overwrite" do
      src = File.join(tmpdir, "dup.txt")
      File.binwrite(src, "d")
      archive = File.join(tmpdir, "dup.zip")
      Omnizip.compress_file(src, archive)

      dest = File.join(tmpdir, "dup-out")
      expect do
        Omnizip::Parallel::ParallelExtractor.new(threads: 2)
          .extract(archive, dest)
        Omnizip::Parallel::ParallelExtractor.new(threads: 2)
          .extract(archive, dest)
      end.to raise_error(Errno::EEXIST)
    end

    it "raises for a missing archive" do
      expect do
        described_class.extract_archive(File.join(tmpdir, "nope.zip"),
                                        File.join(tmpdir, "x"))
      end.to raise_error(Errno::ENOENT)
    end
  end

  describe Omnizip::Parallel::JobScheduler do
    let(:jobs) { [10, 20, 30, 40] }

    it "schedules with every documented strategy" do
      %i[dynamic static round_robin bin_packing].each do |strategy|
        scheduler = described_class.new(strategy: strategy)
        assignments = scheduler.schedule_jobs(jobs, worker_count: 2)

        expect(assignments).not_to be_empty,
                                   "#{strategy} produced no assignments"
      end
    end

    it "distributes all jobs across workers with round robin" do
      scheduler = described_class.new(strategy: :round_robin)
      assignments = scheduler.schedule_jobs(jobs, worker_count: 2)

      expect(assignments.values.flatten.size).to eq(4)
      expect(assignments[0]).to eq([10, 30])
      expect(assignments[1]).to eq([20, 40])
    end

    it "packs large jobs first with bin packing" do
      scheduler = described_class.new(strategy: :bin_packing)
      assignments = scheduler.schedule_jobs(jobs, worker_count: 2)

      expect(assignments.values.flatten.sort).to eq(jobs.sort)
      loads = assignments.values.map(&:sum)
      # 40+10 vs 30+20 — both 50; balanced
      expect(loads).to all(eq(50))
    end

    it "rejects unknown strategies" do
      expect do
        described_class.new(strategy: :chaos)
      end.to raise_error(ArgumentError, /Invalid strategy/)
    end
  end

  describe Omnizip::Parallel::JobQueue do
    it "orders large files first within a priority" do
      queue = described_class.new(max_size: 10)
      queue.push_with_size(file: "small.txt", size: 10)
      queue.push_with_size(file: "large.bin", size: 10_000)
      queue.push_with_size(file: "medium.dat", size: 1_000)

      names = []
      names << queue.pop.file until queue.empty?
      expect(names).to eq(%w[large.bin medium.dat small.txt])
    end
  end

  describe Omnizip::Parallel::WorkerPool do
    it "runs batch work and collects results" do
      pool = described_class.new(worker_class: ParallelSpecDoublingWorker,
                                 num_workers: 2)
      pool.start
      pool.submit_batch([1, 2, 3].map { |n| Fractor::Work.new({ value: n }) })
      pool.run

      values = pool.successful_results.map(&:result).sort
      expect(values).to eq([2, 4, 6])
      expect(pool.failed_results).to be_empty

      pool.shutdown
    end
  end
end
