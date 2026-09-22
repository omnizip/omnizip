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
# rubocop's plugin loader auto-declares this via standard's
# default_lint_roller_plugin metadata where the gem is present; on
# runners without it the require crashes rubocop outright. Ship it in
# the bundle so the load always resolves (its plugin is inert without
# a .standard.yml).
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "thor"

# Parallel processing with Fractor
gem "fractor"

# Documentation pipeline (rake docs:build) — AsciiDoc/Markdown -> static
# HTML via Coradoc; replaces the old Jekyll site. Pinned to the coradoc
# fix for TocEntry#children (metanorma/coradoc#255, merged as PR #256)
# until it ships in a release — then switch to plain released gems.
# Ref = coradoc main at merge time (the pre-rebase branch would rot).
CORADOC_FIX_REF = "550e91c8d6f12171d45f6ff3bfd4e2d7de9be076"
gem "coradoc", git: "https://github.com/metanorma/coradoc.git",
               ref: CORADOC_FIX_REF, glob: "coradoc/*.gemspec"
gem "coradoc-adoc", git: "https://github.com/metanorma/coradoc.git",
                    ref: CORADOC_FIX_REF, glob: "coradoc-adoc/*.gemspec"
gem "coradoc-html", git: "https://github.com/metanorma/coradoc.git",
                    ref: CORADOC_FIX_REF, glob: "coradoc-html/*.gemspec"
