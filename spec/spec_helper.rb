# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

require "omnizip"

module SpecHelpers
  module_function

  # Check if an external command is available
  def command_available?(cmd)
    # Try to run the command with --version or similar harmless flag
    system("#{cmd} --version > #{File::NULL} 2>&1") ||
      system("#{cmd} -? > #{File::NULL} 2>&1") ||
      system("which #{cmd} > #{File::NULL} 2>&1") ||
      system("where #{cmd} > #{File::NULL} 2>&1")
  rescue Errno::ENOENT
    false
  end

  # Check if running on Windows
  def windows?
    Gem.win_platform?
  end

  # Check if unrar command is available
  # On Windows, WinRAR installs UnRAR.exe, on Unix it's just 'unrar'
  def unrar_available?
    return @unrar_available if defined?(@unrar_available)

    @unrar_available = if windows?
                         # On Windows, try UnRAR.exe first (WinRAR install location)
                         command_available?("UnRAR") ||
                           system("UnRAR > #{File::NULL} 2>&1")
                       else
                         command_available?("unrar")
                       end
  end

  # Get the unrar command name for the current platform
  def unrar_command
    windows? ? "UnRAR" : "unrar"
  end

  # Check if xz command is available
  def xz_available?
    return @xz_available if defined?(@xz_available)

    @xz_available = command_available?("xz")
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Use documentation format for clearer output
  config.default_formatter = "doc" if config.files_to_run.one?

  # Print slow examples for debugging
  # config.profile_examples = 10
  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Include helpers in all specs
  config.include SpecHelpers
end
