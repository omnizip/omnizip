# frozen_string_literal: true

require "spec_helper"
require "ripper"
require "set"

# Static analysis for the track-07 `# allowed:` convention.
#
# Lexer-based rather than substring-based: a `# allowed:` inside a string
# literal is not a comment token, and a `respond_to?` inside a heredoc is not
# an identifier token, so neither can fool the check.
#
# Kept outside the example group so RuboCop does not see a constant defined
# inside a block.
module RespondToAnnotationCheck
  # Anchored: the comment must OPEN with the marker. Without \A a comment such
  # as "# revisit, this is not # allowed: bogus" would satisfy the gate.
  ALLOWED = /\A#\s*allowed:\s*\S/

  module_function

  # Lines where respond_to? appears as code, not inside a comment or string.
  def code_lines(tokens)
    tokens
      .select { |_pos, type, tok, _state| type == :on_ident && tok == "respond_to?" }
      .map { |(line, _col), _type, _tok, _state| line }
      .uniq
  end

  # Lines carrying a real comment token with a non-empty reason.
  def annotated_lines(tokens)
    tokens
      .select { |_pos, type, tok, _state| type == :on_comment && tok.match?(ALLOWED) }
      .to_set { |(line, _col), _type, _tok, _state| line }
  end
end

# TODO.refactor track 07: `respond_to?` is never used for type checking.
#
# This enforces syntax, not justification: every remaining occurrence must
# carry a stated reason, so the next reader does not have to re-derive it.
# Whether the reason is a good one stays a review question.
#
# Most survivors are genuine feature detection. One is not: `algorithms/lzma.rb`
# says outright that it is a deferred type check. See
# TODO.refactor/07-respond-to-replacement.md for the split.
RSpec.describe "respond_to? annotations in lib/" do
  it "annotates every occurrence with a reason" do
    root = File.expand_path("../../lib", __dir__)
    prefix = "#{File.dirname(root)}/"
    paths = Dir.glob(File.join(root, "**", "*.rb"))

    # Without this the whole example passes by inspecting nothing, which reads
    # as proof and is not.
    expect(paths).not_to be_empty, "no Ruby files found under #{root}"

    offenses = paths.flat_map do |path|
      source = File.read(path)
      tokens = Ripper.lex(source)
      annotated = RespondToAnnotationCheck.annotated_lines(tokens)
      lines = source.lines
      relative = path.delete_prefix(prefix)

      RespondToAnnotationCheck
        .code_lines(tokens)
        .reject { |n| annotated.include?(n) || annotated.include?(n - 1) }
        .map { |n| "#{relative}:#{n}: #{lines[n - 1].strip}" }
    end

    expect(offenses).to be_empty, lambda {
      "#{offenses.size} respond_to? occurrence(s) in lib/ without an " \
        "`# allowed:` reason:\n#{offenses.map { |o| "  #{o}" }.join("\n")}\n\n" \
        "Use is_a? or a type hierarchy instead. If the check is genuine " \
        "feature detection on an object we do not control, annotate it with " \
        "`# allowed: <reason>` on the same line or the line above."
    }
  end
end
