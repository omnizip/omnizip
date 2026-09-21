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
      # The loaded cdylib: one handle, lazily opened, thread-safe
      # after initialization (Fiddle::Function is immutable once
      # built; compress/decompress are pure C calls).
      class Library
        # Codecs the cdylib dispatches by name.
        # Names the cdylib dispatches: the codec-level acceleration
        # surface (both directions by default — Rust is the
        # authority; Ruby is the fallback).
        CODECS = %w[
          bzip2 zstd lzma xz lzma-alone lzip
          deflate deflate64 zlib gzip ppmd7 ppmd8
        ].freeze

        class << self
          # The shared handle, or nil when the cdylib cannot load.
          # Load failures are cached: a missing library is a stable
          # condition, not something to re-attempt per call.
          def instance
            return @instance if defined?(@instance)

            @instance = open
          end

          def available?
            !instance.nil?
          end

          # Whether the cdylib dispatches this codec name — exact, or
          # a param-carrying prefix ("ppmd7:o6:m16777216" under
          # "ppmd7").
          def supports?(name)
            CODECS.any? { |c| name == c || name.start_with?("#{c}:") }
          end

          # Drop the cached handle so resolution reruns (test seam:
          # specs exercising fallback/absence paths need a clean
          # slate; production never calls this).
          def forget!
            # Remove the ivar entirely: assigning nil would leave it
            # defined, and `instance`'s `defined?` guard would return
            # the nil forever without ever re-opening the library.
            remove_instance_variable(:@instance) if defined?(@instance)
            nil
          end

          # Built lazily: the Fiddle::TYPE_* constants only resolve
          # after a successful require; environments without fiddle
          # (Ruby 4.0 without the gem) never touch this table.
          def function_table
            {
              last_error: ["ozip_last_error", [], Fiddle::TYPE_VOIDP],
              free: ["ozip_free", %i[voidp size_t], Fiddle::TYPE_VOID],
              compress: [
                "ozip_compress",
                %i[voidp voidp size_t int voidp],
                Fiddle::TYPE_VOIDP,
              ],
              decompress: [
                "ozip_decompress",
                %i[voidp voidp size_t size_t voidp],
                Fiddle::TYPE_VOIDP,
              ],
            }
          end

          # The Rust release the loaded cdylib was built from (e.g.
          # "0.21.108"), read through the ozip_version symbol — the
          # platform-gem smoke gate asserts it matches. nil when the
          # library is absent or predates the symbol.
          def dylib_version
            handle = instance&.instance_handle
            return nil if handle.nil?

            func = Fiddle::Function.new(handle["ozip_version"], [], Fiddle::TYPE_VOIDP)
            ptr = func.call
            ptr.null? ? nil : ptr.to_s
          rescue StandardError
            nil
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

            handle = Fiddle.dlopen(path.to_s)
            funcs = function_table.each_with_object({}) do |(key, (name, args, ret)), h|
              h[key] = Fiddle::Function.new(handle[name], args, ret)
            end
            new(funcs, handle)
          rescue StandardError => e # includes Fiddle::DLError
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

        def initialize(functions, handle = nil)
          @functions = functions.freeze
          @handle = handle
        end

        def compress(codec, data, level)
          out_len = [0].pack("Q")
          ptr = call(:compress, codec, data, data.bytesize, level, out_len)
          take(ptr, out_len.unpack1("Q"))
        end

        def decompress(codec, data, expected_len)
          out_len = [0].pack("Q")
          ptr = call(:decompress, codec, data, data.bytesize, expected_len, out_len)
          take(ptr, out_len.unpack1("Q"))
        end

        # Bind one extra C symbol from the loaded cdylib (the archive
        # surface uses this; Fiddle::Function is immutable once built).
        def bind(symbol, args, ret)
          handle = instance_handle
          raise Error, "cdylib not loaded" if handle.nil?

          Fiddle::Function.new(handle[symbol.to_s], args, ret)
        end

        def last_error
          ptr = @functions[:last_error].call
          ptr.null? ? "unknown error" : ptr.to_s
        end

        # The raw Fiddle::Handle (for extra symbol binds).
        def instance_handle
          @handle
        end

        # Copy out + free one returned buffer (public seam for the
        # archive surface).
        def take_buffer(ptr, len)
          take(ptr, len)
        end

        private

        def call(name, codec, input, input_len, a, out_len)
          ptr = @functions[name].call(codec, input, input_len, a, out_len)
          raise Error, last_error if ptr.null?

          ptr
        end

        # Copy out + free in one breath: the buffer belongs to the
        # Rust allocator and must never outlive ozip_free.
        def take(ptr, len)
          string = ptr.to_s(len)
          @functions[:free].call(ptr, len)
          string
        end
      end

      # Raised when a codec call fails; #message carries the Rust
      # side's last_error text.
      class Error < StandardError; end
    end
  end
end
