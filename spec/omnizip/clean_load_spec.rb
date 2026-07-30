# frozen_string_literal: true

require "spec_helper"
require "english"
require "rbconfig"

# Entry points that reach a stdlib constant the library must have required
# for itself. Kept outside the example group so RuboCop does not see a
# constant defined inside a block.
module CleanLoadCases
  LIB = File.expand_path("../../lib", __dir__)

  ENTRY_POINTS = {
    "IO::Source adapts a bare #read duck" =>
      'd = Object.new; def d.read; "abc"; end; ' \
      "print Omnizip::IO::Source.for(d).read",

    "IO::Sink adapts a bare #write duck" =>
      "d = Object.new; def d.write(x); print x; end; " \
      'Omnizip::IO::Sink.for(d).write("abc")',

    "Formats::Xz.create writes to a duck sink" =>
      'd = Object.new; def d.write(_); print "abc"; end; ' \
      'Omnizip::Formats::Xz.create("hello", d)',

    # Output derives from the call's result. An unconditional `print "abc"`
    # after the call would pass for any return value, including nil.
    "Algorithms::LZMA2XzEncoderAdapter#encode_chunk" =>
      "out = Omnizip::Algorithms::LZMA2XzEncoderAdapter.new" \
      '.encode_chunk("abc"); ' \
      'print(out.is_a?(String) && !out.empty? ? "abc" : "bad: " + out.inspect)',
  }.freeze
end

# Regression proofs for the missing-require class of bug.
#
# These MUST run in a subprocess. In-process examples pass even when the
# library is broken, because spec_helper and sibling specs pull in stringio
# and tempfile as a side effect -- the same load-order masking that let the
# bug ship in the first place.
RSpec.describe "omnizip after a bare require" do
  CleanLoadCases::ENTRY_POINTS.each do |description, body|
    it description do
      script = %(require "omnizip"\n#{body}\n)
      output = IO.popen(
        [RbConfig.ruby, "-I", CleanLoadCases::LIB, "-e", script],
        err: %i[child out],
        &:read
      )
      status = $CHILD_STATUS

      # Both assertions matter: a non-zero exit means the subprocess raised,
      # and stdout proves the call actually produced what it should.
      aggregate_failures do
        expect(status).to be_success, "subprocess exited #{status.exitstatus}: #{output}"
        expect(output).to eq("abc")
      end
    end
  end
end
