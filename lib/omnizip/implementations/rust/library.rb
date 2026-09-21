# frozen_string_literal: true

begin
  # Ruby 4.0 moved fiddle out of the default gems.
  require "fiddle"
  require "pathname"
rescue LoadError
  # :nocov:
end

module Omnizip
  module Implementations
    module Rust
      # The loaded cdylib binding: one handle, lazily opened. The
      # BINDING LAYER is chosen at load (leptris-ruby's model):
      #
      #   1. Fiddle (MRI stdlib — the zero-gem fast path)
      #   2. the ffi gem (JRuby / TruffleRuby ship it bundled; MRI
      #      without fiddle — Ruby 4.0 without the gem — uses it too)
      #   3. unavailable (pure-Ruby core everywhere)
      #
      # OMNIZIP_BINDING=fiddle|ffi forces a layer (spec seam; also the
      # way to prove the ffi path on MRI). `instance` returns a
      # FiddleLibrary or FfiLibrary — both expose the identical
      # surface (compress / decompress / last_error / take_buffer /
      # dylib_version / arch_*), so callers are binding-agnostic.
      class Library
        # Codecs the cdylib dispatches by name: the codec-level
        # acceleration surface (both directions by default — Rust is
        # the authority; Ruby is the fallback).
        CODECS = %w[
          bzip2 zstd lzma xz lzma-alone lzip
          deflate deflate64 zlib gzip ppmd7 ppmd8
        ].freeze

        class << self
          # The shared binding, or nil when no layer can load. Load
          # failures are cached per layer: a missing library is a
          # stable condition, not something to re-attempt per call.
          def instance
            return @instance if defined?(@instance)

            @instance = open
          end

          def available?
            !instance.nil?
          end

          # Which binding loaded: "fiddle", "ffi", or nil.
          def binding_layer
            return nil if instance.nil?

            instance.class.name.end_with?("FfiLibrary") ? "ffi" : "fiddle"
          end

          # Whether the cdylib dispatches this codec name — exact, or
          # a param-carrying prefix ("ppmd7:o6:m16777216" under
          # "ppmd7").
          def supports?(name)
            CODECS.any? { |c| name == c || name.start_with?("#{c}:") }
          end

          # Drop the cached binding so resolution reruns (test seam:
          # specs exercising fallback/absence paths need a clean
          # slate; production never calls this).
          def forget!
            # Remove the ivar entirely: assigning nil would leave it
            # defined, and `instance`'s `defined?` guard would return
            # the nil forever without ever re-opening the library.
            remove_instance_variable(:@instance) if defined?(@instance)
            nil
          end

          # The Rust release the loaded cdylib was built from (e.g.
          # "0.21.112"), read through the ozip_version symbol — the
          # platform-gem smoke gate asserts it matches. nil when the
          # library is absent or predates the symbol.
          def dylib_version
            instance&.dylib_version
          end

          # Resolve the cdylib path. Precedence:
          #
          #   1. OMNIZIP_NO_RUST=1 — hard kill switch (always nil, so
          #      the pure-Ruby core handles everything; also the smoke
          #      gate for "works without Rust").
          #   2. OMNIZIP_FFI_DYLIB — explicit path (developer override).
          #   3. vendor/ — the prebuilt cdylib. Platform gems ship it
          #      here and `rake rust:build` writes here; rubygems
          #      already matched the platform at install time, so no
          #      runtime architecture probing is needed and the wrong
          #      arch cannot be picked.
          #   4. ext/ (legacy location).
          #   5. A sibling omnizip-rs checkout.
          #
          # `dirs` overrides 3-5 (spec seam: staged candidate paths).
          def resolve_path(dirs = nil)
            return nil if ENV.fetch("OMNIZIP_NO_RUST", nil) == "1"

            explicit = ENV.fetch("OMNIZIP_FFI_DYLIB", nil)
            return Pathname.new(explicit) if explicit && File.file?(explicit)

            candidates = dirs || [
              Pathname.new(__dir__).join("../../../../vendor"),
              Pathname.new(__dir__).join("../../../../ext/libomnizip_ffi"),
              *sibling_checkout,
            ]

            %w[.dylib .so .dll].each do |ext|
              candidates.each do |dir|
                path = dir.join("libomnizip_ffi#{ext}")
                return path if path.file?
              end
            end
            nil
          end

          private

          def open
            path = resolve_path
            return nil if path.nil?

            forced = ENV.fetch("OMNIZIP_BINDING", nil)
            if forced != "ffi" && defined?(Fiddle)
              return FiddleLibrary.new(path)
            end

            # The ffi path: JRuby/TruffleRuby bundle the gem; MRI
            # needs it installed (it is a runtime dependency). A
            # forced layer must not silently fall back to another.
            require "ffi"
            FfiLibrary.new(path)
          rescue LoadError, StandardError => e # Fiddle::DLError, FFI::LoadError, ...
            warn "omnizip: rust backend unavailable (#{e.message}); using pure Ruby" if ENV["OMNIZIP_BACKEND"] == "rust"
            nil
          end

          # A sibling omnizip-rs checkout: ../omnizip-rs relative to
          # this gem's repository root.
          def sibling_checkout
            gem_root = Pathname.new(__dir__).join("../../../../..")
            %w[omnizip-rs target/release].map do |rel|
              gem_root.join(rel, "target/release")
            end
          end
        end
      end

      # Raised when a codec call fails; #message carries the Rust
      # side's last_error text.
      class Error < StandardError; end
    end
  end
end
