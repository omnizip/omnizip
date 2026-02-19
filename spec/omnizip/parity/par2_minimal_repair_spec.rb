# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/par2_creator"
require "omnizip/parity/par2_repairer"
require "tmpdir"
require "fileutils"

RSpec.describe "PAR2 Minimal Round-Trip Test" do
  let(:temp_dir) { Dir.mktmpdir("par2_minimal_test") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "creates and repairs a simple 2-file scenario" do
    # Create two small files with known content
    file1 = File.join(temp_dir, "file1.dat")
    file2 = File.join(temp_dir, "file2.dat")

    # Use simple repeating patterns for easy debugging
    content1 = ("A" * 256).b # 256 bytes
    content2 = ("B" * 256).b # 256 bytes

    File.write(file1, content1)
    File.write(file2, content2)

    # Create PAR2 with our creator (uses new encoder)
    creator = Omnizip::Parity::Par2Creator.new(
      redundancy: 50, # High redundancy for safety
      block_size: 256, # One block per file
    )
    creator.add_file(file1)
    creator.add_file(file2)

    base_name = File.join(temp_dir, "test")
    par2_files = creator.create(base_name)

    # Verify PAR2 files were created
    expect(par2_files).not_to be_empty
    expect(File.exist?("#{base_name}.par2")).to be true

    # Simulate damage: delete file1
    FileUtils.rm(file1)
    expect(File.exist?(file1)).to be false

    # Repair using our repairer (uses new decoder)
    repairer = Omnizip::Parity::Par2Repairer.new("#{base_name}.par2")
    result = repairer.repair

    # Check repair succeeded
    expect(result.success?).to be(true),
                               "Repair failed: #{result.error_message}"
    expect(result.recovered_files).to include("file1.dat")

    # Verify recovered file matches original
    recovered = File.binread(file1)
    expect(recovered).to eq(content1),
                         "Recovered content mismatch:\n" \
                         "Expected: #{content1[0, 32].bytes.map do |b|
                           '%02x' % b
                         end.join(' ')}\n" \
                         "Got:      #{recovered[0, 32].bytes.map do |b|
                           '%02x' % b
                         end.join(' ')}"
  end

  it "handles single block per file correctly" do
    # Even simpler: one file, one block
    file1 = File.join(temp_dir, "single.dat")
    content = ("X" * 100).b
    File.write(file1, content)

    # Create PAR2
    creator = Omnizip::Parity::Par2Creator.new(
      redundancy: 100, # 1:1 redundancy
      block_size: 128,
    )
    creator.add_file(file1)

    base_name = File.join(temp_dir, "single")
    creator.create(base_name)

    # Delete and repair
    FileUtils.rm(file1)
    repairer = Omnizip::Parity::Par2Repairer.new("#{base_name}.par2")
    result = repairer.repair

    expect(result.success?).to be true
    recovered = File.binread(file1)
    expect(recovered).to eq(content)
  end
end
