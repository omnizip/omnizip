# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in omnizip.gemspec
gemspec

# For spec testing
gem "csv"
gem "rake"
gem "rspec"
# Pinned: CI resolves dependencies fresh (no lockfile), and rubocop
# 1.91 changed Metrics/BlockLength scoping + plugin loading, which
# resurrected ~190 dormant spec offenses and crashes on the inherited
# oss-guides `standard-custom` require. Re-pin after triage upstream.
gem "rubocop", "1.90.0"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "thor"

# Parallel processing with Fractor
gem "fractor"
