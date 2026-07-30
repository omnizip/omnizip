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

  # Constants referenced in code. Comments and string literals lex as
  # :on_comment / :on_tstring_content, so they cannot trigger a violation.
  def referenced_constants(source)
    Ripper.lex(source)
      .select { |_pos, type, _tok, _state| type == :on_const }
      .map { |_pos, _type, tok, _state| tok }
      .uniq
  end

  # Features required by a top-level, unconditional statement in the file
  # prologue. Anything conditional, nested in a method, or inside a class or
  # module body is wrapped in an enclosing node and so is not a direct child
  # of the program's root statement list.
  def prologue_requires(source)
    sexp = Ripper.sexp(source)
    return [] unless sexp && sexp[0] == :program

    sexp[1].each_with_object([]) do |node, features|
      break features if declaration?(node)

      feature = required_feature(node)
      features << feature if feature
    end
  end

  def declaration?(node)
    node.is_a?(Array) && DECLARATIONS.include?(node[0])
  end

  # Accepts both `require "x"` (:command) and `require("x")`
  # (:method_add_arg wrapping an :fcall).
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

    args.flatten.grep(String).first
  end
end

# Checked without loading anything, so load order cannot mask a violation --
# which is what made this class of bug survive in the first place.
RSpec.describe "stdlib constant requires in lib/" do
  it "requires every guarded constant it references" do
    root = File.expand_path("../../lib", __dir__)
    prefix = "#{File.dirname(root)}/"

    violations = Dir.glob(File.join(root, "**", "*.rb")).flat_map do |path|
      source = File.read(path)
      referenced = ConstantRequireCheck.referenced_constants(source)
      required = ConstantRequireCheck.prologue_requires(source)

      ConstantRequireCheck::GUARDED
        .select { |const, feature| referenced.include?(const) && !required.include?(feature) }
        .map { |const, feature| "#{path.delete_prefix(prefix)}: #{const} (add require \"#{feature}\")" }
    end

    expect(violations).to be_empty, lambda {
      "#{violations.size} file(s) reference a stdlib constant without a " \
        "top-level require in the file prologue:\n" \
        "#{violations.map { |v| "  #{v}" }.join("\n")}\n\n" \
        "The require must be a top-level, unconditional statement before " \
        "the first class/module. Both `require \"x\"` and `require(\"x\")` " \
        "are accepted."
    }
  end
end
