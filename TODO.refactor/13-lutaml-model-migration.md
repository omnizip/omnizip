# 13 — lutaml-model migration

Priority: **medium**.
Status: TODO (large; this pass establishes the pattern, full migration
is follow-up).

## Rule

> ALL (de)serialization goes through the framework. Declare attributes
> with `attribute :name, :type`. Declare wire names with a `mapping do
> ... end` block. Never write `def to_h` / `def from_h` / `def to_json`
> / `def from_json` on a model class.

## Inventory

26 `def to_h` occurrences across 22 files. 2 `def to_json`. None use
lutaml-model today even though the gemspec declares the dependency.

### Models (lib/omnizip/models/)

- `compression_options.rb` (`to_h`, `to_json`)
- `algorithm_metadata.rb` (`to_h`, `to_json`)
- `conversion_result.rb`
- `eta_result.rb`
- `filter_config.rb`
- `match_result.rb`
- `optimization_suggestion.rb`
- `parallel_options.rb`
- `performance_result.rb`
- `profile_report.rb`
- `progress_options.rb`
- `conversion_options.rb`

### Format entry/metadata classes

- `formats/xar/entry.rb`
- `formats/zip/unix_extra_field.rb`
- `formats/rpm/header.rb`
- `metadata/entry_metadata.rb`
- `metadata/archive_metadata.rb`

### Other

- `progress/operation_progress.rb`
- `profile/profile_registry.rb`, `custom_profile.rb`, `compression_profile.rb`
- `link_handler/symbolic_link.rb`, `hard_link.rb`

## Plan (this pass)

1. Establish the pattern by migrating **two representative models**:
   `Omnizip::Models::CompressionOptions` and
   `Omnizip::Models::AlgorithmMetadata`. Convert to lutaml-model:
   ```ruby
   class CompressionOptions < Lutaml::Model::Serializable
     attribute :algorithm, :string
     attribute :level, :integer, default: 6
     # ...
     mapping do
       map :algorithm, to: :algorithm
       map :level, to: :level
     end
   end
   ```
   The framework provides `to_hash`, `to_json`, `from_hash`,
   `from_json` automatically — remove the hand-rolled versions.

2. Delete the manual `to_h` / `to_json` from those two files.

3. Document the migration recipe in this TODO file for the remaining
   models.

## Acceptance

- Two models migrated; their specs still pass.
- `grep -rn "def to_h\|def to_json" lib/omnizip/models/` count drops by
  at least 2.

## Remaining work (future pass)

Migrate the other ~24 files following the established recipe. The
metadata/entry classes likely share structure and may collapse into a
smaller set of richer models — review for MECE opportunities.
