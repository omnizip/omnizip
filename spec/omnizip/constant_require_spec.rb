# frozen_string_literal: true

require "spec_helper"
require "ripper"

# Static analysis for "a file that references a constant requires it".
#
# Kept outside the example group so RuboCop does not see constants defined
# inside a block.
module ConstantRequireCheck
  GUARDED = { "StringIO" => "stringio", "Tempfile" => "tempfile" }.freeze
  DECLARATIONS = %i[class module].freeze

  module_function

  # Position of each constant's FIRST reference in code, as [line, column].
  # Comments and string literals lex as :on_comment / :on_tstring_content, so
  # they cannot trigger a violation.
  def first_constant_positions(source)
    Ripper.lex(source)
      .select { |_pos, type, _tok, _state| type == :on_const }
      .reverse_each
      .to_h { |pos, _type, tok, _state| [tok, pos] }
  end

  # Position of each feature required by a top-level, unconditional statement
  # in the file prologue, as [line, column]. Anything conditional, nested in a
  # method, or inside a class or module body is wrapped in an enclosing node
  # and so is not a direct child of the program's root statement list.
  def prologue_require_positions(source)
    sexp = Ripper.sexp(source)
    return {} unless sexp && sexp[0] == :program

    sexp[1].each_with_object({}) do |node, positions|
      break positions if declaration?(node)

      feature, pos = required_feature(node)
      positions[feature] ||= pos if feature
    end
  end

  def declaration?(node)
    node.is_a?(Array) && DECLARATIONS.include?(node[0])
  end

  # Accepts both `require "x"` (:command) and `require("x")`
  # (:method_add_arg wrapping an :fcall). Returns [feature, [line, column]].
  def required_feature(node)
    return unless node.is_a?(Array)

    ident, args =
      case node[0]
      when :command        then [node[1],    node[2]]
      when :method_add_arg then [node[1][1], node[2]]
      end
    return unless ident.is_a?(Array) &&
      ident[0] == :@ident &&
      ident[1] == "require"

    feature = string_literal_argument(args)
    [feature, ident[2]] if feature
  end

  # Only a plain string literal counts. `require File.join("a", "b")` must not
  # be read as requiring "a", so anything that is not a lone :string_literal
  # is ignored rather than guessed at.
  def string_literal_argument(args)
    parts = args.is_a?(Array) && args[0] == :arg_paren ? args[1] : args
    return unless parts.is_a?(Array) && parts[0] == :args_add_block

    list = parts[1]
    return unless list.is_a?(Array) && list.size == 1

    literal = list[0]
    return unless literal.is_a?(Array) && literal[0] == :string_literal

    # Exactly one :@tstring_content child. Interpolation adds a
    # :string_embexpr sibling, which fails the size check.
    content = literal[1]
    return unless content.is_a?(Array) &&
      content[0] == :string_content &&
      content.size == 2

    token = content[1]
    return unless token.is_a?(Array) && token[0] == :@tstring_content

    token[1]
  end
end

# Checked without loading anything, so load order cannot mask a violation --
# which is what made this class of bug survive in the first place.
RSpec.describe "stdlib constant requires in lib/" do
  it "requires every guarded constant it references" do
    root = File.expand_path("../../lib", __dir__)
    prefix = "#{File.dirname(root)}/"
    paths = Dir.glob(File.join(root, "**", "*.rb"))

    # Without this the whole example passes by inspecting nothing, which reads
    # as proof and is not.
    expect(paths).not_to be_empty, "no Ruby files found under #{root}"

    violations = paths.flat_map do |path|
      source = File.read(path)
      used_at = ConstantRequireCheck.first_constant_positions(source)
      required_at = ConstantRequireCheck.prologue_require_positions(source)

      ConstantRequireCheck::GUARDED.filter_map do |const, feature|
        use = used_at[const]
        next unless use

        req = required_at[feature]
        next if req && (req <=> use).negative?

        reason = req ? "require \"#{feature}\" comes after it" : "add require \"#{feature}\""
        "#{path.delete_prefix(prefix)}:#{use.first}: #{const} (#{reason})"
      end
    end

    expect(violations).to be_empty, lambda {
      "#{violations.size} guarded constant reference(s) in lib/ not preceded " \
        "by a top-level require:\n" \
        "#{violations.map { |v| "  #{v}" }.join("\n")}\n\n" \
        "The require must be a top-level, unconditional statement in the file " \
        "prologue, before the first class/module AND before the constant's " \
        "first use. Both `require \"x\"` and `require(\"x\")` are accepted."
    }
  end
end
