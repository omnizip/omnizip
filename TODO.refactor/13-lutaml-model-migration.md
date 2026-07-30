# 13 — lutaml-model migration

Priority: **medium**.
Status: DONE for the models that should migrate. The remaining `to_h`
methods are deliberate — see "Why 17 stay" below.

## Rule

> ALL (de)serialization goes through the framework. Declare attributes
> with `attribute :name, :type`. Declare wire names with a `mapping do
> ... end` block. Never write `def to_h` / `def from_h` / `def to_json`
> / `def from_json` on a model class.

## Result

Six models now inherit `Lutaml::Model::Serializable`:

- `CompressionOptions`, `AlgorithmMetadata` (earlier pass)
- `ConversionOptions`, `ProgressOptions`, `ETAResult`, `ParallelOptions`

Counts, measured against the tree rather than estimated:

| Metric | Before | After |
| --- | --- | --- |
| `grep -rn "def to_h" lib/ \| wc -l` | 21 | 17 |
| Same under `lib/omnizip/models/` | 10 | 6 |
| `def to_json` / `from_h` / `from_json` in `lib/` | 0 | 0 |

An earlier version of this document claimed "26 `def to_h` across 22
files, 2 `def to_json`". Both were wrong; the numbers above are real.

## The symbol-type blocker was not real

This document previously held `ConversionOptions` back pending "lutaml
symbol-type support". There is nothing to wait for. `:symbol` is a
built-in type: it is registered in `TYPE_CODES` in
`lib/lutaml/model/type.rb` and implemented in
`lib/lutaml/model/type/symbol.rb`, in the 0.8 line the gemspec's
`~> 0.7` already resolves to. It casts symbols, strings, and nil
correctly and round-trips through JSON. `ConversionOptions` uses it for
`source_format`, `target_format`, `compression`, and `filter`.

## Recipe

```ruby
require "lutaml/model"

class Thing < Lutaml::Model::Serializable
  attribute :level, :integer, default: 5
  attribute :name, :string

  key_value do
    map "level", to: :level, render_default: true, render_nil: true
    map "name", to: :name, render_default: true, render_nil: true
  end
end
```

`key_value` covers hash, YAML, TOML, and JSON in one declaration.

### Two behaviours that will catch you out

**1. `to_hash` returns String keys.** The hand-rolled `to_h` methods
returned Symbol keys. These are not interchangeable, and
`Serializable` does not define `to_h` at all — calling it raises
`NoMethodError`. Removing `to_h` is a breaking change for any external
caller.

**2. `render_default: true` alone does not give you a fixed key set.**
It renders an unassigned default, but still drops a key that was
explicitly assigned `nil`:

| Mapping | fresh `.new` | after `x.a = nil` |
| --- | --- | --- |
| `render_default: true` | `{"a" => 5}` | `{}` |
| `+ render_nil: true` | `{"a" => 5, "b" => nil}` | `{"a" => nil}` |

Use **both** flags when the old `to_h` emitted every key. Use
`render_default` alone when it ended in `.compact`. Use neither when
there are no defaults and nils were dropped. There is no class-level or
global switch — `render_default:` is per-rule and defaults to `false`.

### Other gotchas

- Lambda defaults (`default: -> { detect_cpu_count }`) are evaluated
  with `self` bound to the **instance**. A private instance method
  works; a class method raises `NameError`.
- `dup` shares the internal `@using_default` hash. With both render
  flags set this is unobservable, so no `dup` override or
  `initialize_copy` hook is needed.
- Unknown keyword arguments to `.new` are silently ignored, where a
  plain-Ruby `initialize` would raise `ArgumentError`.
- `self.class.attributes` returns a `Hash{Symbol=>Attribute}`. Iterate
  it with `each_key`.

## Why 17 `to_h` methods stay

These are computed reports, projections over another object, or
wire-format builders — not serializations of the receiver's own state.
Converting them would drop the computed fields or force a second method
back onto the class. Leave them alone.

| File | Reason |
| --- | --- |
| `models/conversion_result.rb` | Three computed fields; drops a stored one |
| `models/match_result.rb` | Keys don't match attributes; renames and computes |
| `models/optimization_suggestion.rb` | Computed `priority_score`; ctor validates enums |
| `models/performance_result.rb` | Computed fields plus `timestamp.iso8601` |
| `models/profile_report.rb` | Nested computed `summary:`; maps nested results |
| `models/filter_config.rb` | Emits `:name` for `@name_sym`; binary properties; registry lookups |
| `formats/rpm/header.rb` | Tag-map projection over a collection |
| `formats/xar/entry.rb` | XAR XML attributes; octal mode, formatted timestamps |
| `formats/zip/unix_extra_field.rb` | Emits a constant tag; wire format is manual pack |
| `metadata/entry_metadata.rb` | Pure delegation; stores no attributes of its own |
| `metadata/archive_metadata.rb` | Computed aggregates |
| `profile/compression_profile.rb` | `CustomProfile#to_h` calls `super` on it |
| `profile/custom_profile.rb` | Inheritance chain over `to_h` |
| `profile/profile_registry.rb` | Registry projection under a mutex |
| `progress/operation_progress.rb` | Computed percentages and elapsed time |
| `link_handler/symbolic_link.rb` | Type discriminator; storage uses `serialize` |
| `link_handler/hard_link.rb` | Type discriminator; storage uses `serialize` |

Because these stay, `grep "def to_h" lib/` will never reach zero. That
is the intended end state, not unfinished work.

## Follow-up work

1. **Rename the 17.** If they are reports and projections, `to_h` is
   the wrong name — that is the real defect. Suggested groupings:
   `to_report` for the computed ones, `to_tag_map` / `to_attributes`
   for projections, `to_xml_attributes` / `to_fields` for wire-format
   builders. Each rename is itself a public-API break.
2. **Fix `apply` in `CompressionOptions` and `AlgorithmMetadata`.**
   Both iterate `self.class.attributes.each do |attr| ... attr.name`,
   but `attributes` is a Hash, so the block gets a two-element Array
   and `attr.name` raises `NoMethodError`. Neither has a caller or a
   spec today, which is why it went unnoticed. Fix is `each_key`, plus
   a spec per class.
3. **Extract the shared `apply` loop** once (2) has landed — three
   classes now carry a similar body.
4. **Consider `FilterConfig` and the profile classes** for a proper
   migration; both were judged too high-blast-radius to bundle here.
