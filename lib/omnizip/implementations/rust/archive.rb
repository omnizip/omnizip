# frozen_string_literal: true

module Omnizip
  module Implementations
    module Rust
      # Whole-archive acceleration over the cdylib: open any supported
      # format (auto-detected), list entries, read entry bytes. This is
      # the archive-level tier surface — the Ruby core remains the
      # fallback (the cdylib unavailable ⇒ these raise LibraryMissing
      # and callers fall back).
      class Archive
        class LibraryMissing < StandardError; end

        # Built lazily inside #initialize: the Fiddle::TYPE_* constants
        # only resolve after a successful require, and Ruby 4.0 moved
        # fiddle out of the default gems (same reason
        # Library.function_table is a method, not a constant).
        def initialize(data, password: nil)
          lib = Library.instance
          raise LibraryMissing, "omnizip-ffi cdylib not loaded" unless lib

          @lib = lib
          funcs = function_table
          @funcs = funcs.each_with_object({}) do |(key, (name, args, ret)), h|
            h[key] = lib.bind(name, args, ret)
          end

          pw = password&.to_s
          pw_ptr = pw && !pw.empty? ? Fiddle::Pointer[pw] : nil
          @handle = @funcs[:arch_open].call(Fiddle::Pointer[data], data.bytesize, pw_ptr)
          return unless @handle.null?

          raise Error, @lib.last_error
        end

        def entry_count
          @funcs[:arch_count].call(@handle)
        end

        def entry_names
          (0...entry_count).map do |i|
            ptr = @funcs[:arch_entry_name].call(@handle, i)
            next nil if ptr.null?

            ptr.to_s
          end
        end

        def entry_size(index)
          @funcs[:arch_entry_size].call(@handle, index)
        end

        # Read one entry's uncompressed bytes.
        #
        # @return [String] binary
        def read_entry(index)
          out_len = [0].pack("Q")
          ptr = @funcs[:arch_read_entry].call(@handle, index, out_len)
          raise Error, @lib.last_error if ptr.null?

          @lib.take_buffer(ptr, out_len.unpack1("Q"))
        end

        def close
          return unless @handle

          @funcs[:arch_close].call(@handle)
          @handle = nil
        end

        def self.open(data, password: nil)
          archive = new(data, password: password)
          yield archive
        ensure
          archive&.close
        end

        private

        def function_table
          {
            arch_open: ["ozip_arch_open", %i[voidp size_t voidp], Fiddle::TYPE_VOIDP],
            arch_count: ["ozip_arch_count", [:voidp], Fiddle::TYPE_SIZE_T],
            arch_entry_name: ["ozip_arch_entry_name", %i[voidp size_t], Fiddle::TYPE_VOIDP],
            arch_entry_size: ["ozip_arch_entry_size", %i[voidp size_t], Fiddle::TYPE_VOIDP],
            arch_read_entry: ["ozip_arch_read_entry", %i[voidp size_t voidp], Fiddle::TYPE_VOIDP],
            arch_close: ["ozip_arch_close", [:voidp], Fiddle::TYPE_VOID],
          }
        end
      end
    end
  end
end
