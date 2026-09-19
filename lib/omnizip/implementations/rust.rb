# frozen_string_literal: true

module Omnizip
  module Implementations
    # Rust-accelerated codec backend (TODO.ref-parity/62).
    #
    # Loads the omnizip-ffi cdylib through stdlib Fiddle — no
    # compiled Ruby extension, no rake-compiler. When the library
    # is unavailable the gem transparently stays on the pure-Ruby
    # path; nothing about the fallback is an error.
    #
    # Library resolution order:
    #   1. ENV['OMNIZIP_FFI_DYLIB'] (explicit path)
    #   2. ../target/release/ inside a sibling omnizip-rs checkout
    #
    # Tier policy (see Omnizip::Backends): decode is always
    # output-invariant, so `auto` uses Rust for decode whenever
    # available; encode uses Rust only when byte-identity with the
    # pure-Ruby encoder has been verified for that codec
    # (RUST_ENCODE_IDENTICAL), keeping content addressing stable.
    module Rust
      autoload :Library, "omnizip/implementations/rust/library"
    end
  end
end
