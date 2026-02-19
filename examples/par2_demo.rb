#!/usr/bin/env ruby
# frozen_string_literal: true

# PAR2 Parity Archive Demo
# Demonstrates creating, verifying, and repairing files with PAR2 error correction

require "bundler/setup"
require "omnizip/parity"
require "tempfile"
require "fileutils"

def demo_par2_workflow
  puts "=== PAR2 Parity Archive Demo ==="
  puts

  # Create temporary directory for demo
  temp_dir = Dir.mktmpdir("par2_demo")

  begin
    # Step 1: Create test files
    puts "Step 1: Creating test files..."
    file1 = File.join(temp_dir, "important_data.txt")
    file2 = File.join(temp_dir, "documents.txt")

    File.write(file1, "This is important data! " * 100)
    File.write(file2, "These are valuable documents. " * 100)
    puts "  ✓ Created test files (#{File.size(file1) + File.size(file2)} bytes total)"
    puts

    # Step 2: Create PAR2 protection
    puts "Step 2: Creating PAR2 recovery files with 10% redundancy..."
    creator = Omnizip::Parity::Par2Creator.new(
      redundancy: 10,
      block_size: 1024,
      progress: ->(pct, msg) { puts "  [#{pct}%] #{msg}" },
    )

    creator.add_file(file1)
    creator.add_file(file2)

    par2_files = creator.create(File.join(temp_dir, "backup"))
    puts "  ✓ Created #{par2_files.size} PAR2 files"
    par2_files.each { |f| puts "    - #{File.basename(f)}" }
    puts

    # Step 3: Verify intact files
    puts "Step 3: Verifying file integrity..."
    verifier = Omnizip::Parity::Par2Verifier.new(par2_files.first)
    result = verifier.verify

    if result.all_ok?
      puts "  ✓ All files intact!"
      puts "    Total blocks: #{result.total_blocks}"
      puts "    Recovery blocks: #{result.recovery_blocks}"
    else
      puts "  ✗ Verification failed (unexpected!)"
    end
    puts

    # Step 4: Simulate corruption
    puts "Step 4: Simulating file corruption..."
    corrupted_content = "CORRUPTED DATA! " * 100
    File.write(file1, corrupted_content)
    puts "  ✓ Corrupted #{File.basename(file1)}"
    puts

    # Step 5: Verify corrupted file
    puts "Step 5: Verifying corrupted files..."
    result2 = verifier.verify

    if result2.all_ok?
      puts "  ✗ No corruption detected (unexpected!)"
    else
      puts "  ✓ Detected corruption:"
      puts "    Damaged files: #{result2.damaged_files.join(', ')}"
      puts "    Damaged blocks: #{result2.damaged_blocks.size}"
      puts "    Repairable: #{result2.repairable?}"
    end
    puts

    # Step 6: Repair damaged file
    if result2.repairable?
      puts "Step 6: Repairing corrupted files..."
      repairer = Omnizip::Parity::Par2Repairer.new(
        par2_files.first,
        progress: ->(pct, msg) { puts "  [#{pct}%] #{msg}" },
      )

      repair_result = repairer.repair

      if repair_result.success?
        puts "  ✓ Repair successful!"
        puts "    Recovered files: #{repair_result.recovered_files.join(', ')}"
        puts "    Recovered blocks: #{repair_result.recovered_blocks}"

        # Verify repair worked
        result3 = verifier.verify
        if result3.all_ok?
          puts "  ✓ Verification after repair: All files intact!"
        else
          puts "  ✗ Verification after repair failed"
        end
      else
        puts "  ✗ Repair failed: #{repair_result.error_message}"
      end
    else
      puts "Step 6: Cannot repair - insufficient recovery blocks"
    end
  ensure
    # Cleanup
    puts
    puts "Cleaning up temporary files..."
    FileUtils.rm_rf(temp_dir)
    puts "Demo complete!"
  end
end

# Run the demo
if __FILE__ == $PROGRAM_NAME
  demo_par2_workflow
end
