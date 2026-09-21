# frozen_string_literal: true

module Omnizip
  module Implementations
    module Rust
      # The ffi-gem binding of the cdylib's C ABI — the JRuby /
      # TruffleRuby acceleration path (leptris-ruby's model): those
      # engines ship no Fiddle, so the Fiddle tier cannot load.
      # Mirrors FiddleLibrary's public surface exactly, so the Library
      # facade and the Archive class are binding-agnostic.
      class FfiLibrary
        attr_reader :mod

        # Attach via a fresh module: FFI::Library is an extend-time
        # DSL — one module per loaded image, like one Fiddle::Handle.
        def self.attach(path)
          mod = Module.new do
            extend ::FFI::Library

            ffi_lib path.to_s
          end
          mod.attach_function :ozip_compress,
                              %i[string buffer_in size_t int pointer], :pointer
          mod.attach_function :ozip_decompress,
                              %i[string buffer_in size_t size_t pointer], :pointer
          mod.attach_function :ozip_last_error, [], :pointer
          mod.attach_function :ozip_free, %i[pointer size_t], :void
          mod.attach_function :ozip_version, [], :pointer
          mod.attach_function :ozip_arch_open,
                              %i[buffer_in size_t string], :pointer
          mod.attach_function :ozip_arch_count, [:pointer], :size_t
          mod.attach_function :ozip_arch_entry_name,
                              %i[pointer size_t], :pointer
          mod.attach_function :ozip_arch_entry_size,
                              %i[pointer size_t], :uint64
          mod.attach_function :ozip_arch_read_entry,
                              %i[pointer size_t pointer], :pointer
          mod.attach_function :ozip_arch_close, [:pointer], :void
          mod
        end

        def initialize(path)
          @mod = self.class.attach(path)
        end

        def compress(codec, data, level)
          out_len = ::FFI::MemoryPointer.new(:size_t)
          ptr = mod.ozip_compress(codec, data, data.bytesize, level, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.read_ulong)
        end

        def decompress(codec, data, expected_len)
          out_len = ::FFI::MemoryPointer.new(:size_t)
          ptr = mod.ozip_decompress(codec, data, data.bytesize,
                                    expected_len, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.read_ulong)
        end

        def last_error
          ptr = mod.ozip_last_error
          ptr.null? ? "unknown error" : ptr.read_string
        end

        # Copy out + free one returned buffer: the buffer belongs to
        # the Rust allocator and must never outlive ozip_free.
        def take(ptr, len)
          s = ptr.read_string(len)
          mod.ozip_free(ptr, len)
          s
        end

        def take_buffer(ptr, len)
          take(ptr, len)
        end

        # The Rust release this cdylib was built from, or nil when the
        # symbol is absent (dylibs older than 0.21.109).
        def dylib_version
          ptr = mod.ozip_version
          ptr.null? ? nil : ptr.read_string
        rescue ::FFI::NotFoundError
          nil
        end

        # ---- whole-archive surface (ArchHandle) ----
        # FFI auto-converts a Ruby String for a :pointer argument and
        # nil to NULL, and the handle travels as a naked pointer.

        def arch_open(data, password)
          ptr = mod.ozip_arch_open(data, data.bytesize, password)
          raise Rust::Error, last_error if ptr.null?

          ptr
        end

        def arch_count(handle)
          mod.ozip_arch_count(handle)
        end

        def arch_entry_name(handle, index)
          ptr = mod.ozip_arch_entry_name(handle, index)
          ptr.null? ? nil : ptr.read_string
        end

        def arch_entry_size(handle, index)
          mod.ozip_arch_entry_size(handle, index)
        end

        def arch_read_entry(handle, index)
          out_len = ::FFI::MemoryPointer.new(:size_t)
          ptr = mod.ozip_arch_read_entry(handle, index, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.read_ulong)
        end

        def arch_close(handle)
          mod.ozip_arch_close(handle)
        end
      end
    end
  end
end
