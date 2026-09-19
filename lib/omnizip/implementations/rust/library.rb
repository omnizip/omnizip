# frozen_string_literal: true

require "fiddle"

module Omnizip
  module Implementations
    module Rust
      # The loaded cdylib: one handle, lazily opened, thread-safe
      # after initialization (Fiddle::Function is immutable once
      # built; compress/decompress are pure C calls).
      class Library
        NAMES = {
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
        }.freeze

        # Codecs the cdylib dispatches by name.
        CODECS = %w[bzip2 zstd lzma xz].freeze

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

          private

          def open
            path = resolve_path
            return nil if path.nil?

            handle = Fiddle.dlopen(path.to_s)
            funcs = NAMES.each_with_object({}) do |(key, (name, args, ret)), h|
              h[key] = Fiddle::Function.new(handle[name], args, ret)
            end
            new(funcs)
          rescue StandardError, Fiddle::DLError => e
            warn "omnizip: rust backend unavailable (#{e.message}); using pure Ruby" if ENV["OMNIZIP_BACKEND"] == "rust"
            nil
          end

          def resolve_path
            explicit = ENV.fetch("OMNIZIP_FFI_DYLIB", nil)
            return Pathname.new(explicit) if explicit && File.file?(explicit)

            candidates = [
              Pathname.new(__dir__).join("../../../../ext/libomnizip_ffi"),
              sibling_checkout,
            ].compact.flatten

            %w[.dylib .so].each do |ext|
              candidates.each do |dir|
                path = dir.join("libomnizip_ffi#{ext}")
                return path if path.file?
              end
            end
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

        def initialize(functions)
          @functions = functions.freeze
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

        def last_error
          ptr = @functions[:last_error].call
          ptr.null? ? "unknown error" : ptr.to_s
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
