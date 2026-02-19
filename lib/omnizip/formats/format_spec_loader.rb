# frozen_string_literal: true

require "yaml"
begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require_relative "../error"

module Omnizip
  module Formats
    # Loads and manages format specifications from YAML configuration files
    #
    # This class provides a configuration-driven architecture for archive formats,
    # allowing format specifications to be externalized in YAML files rather than
    # hardcoded in the application.
    #
    # @example Loading a format specification
    #   spec = FormatSpecLoader.load("rar5")
    #   spec.format.name # => "RAR5"
    #   spec.format.magic_bytes # => [0x52, 0x61, 0x72, ...]
    #
    # @example Getting all loaded specifications
    #   specs = FormatSpecLoader.all_specs
    #   specs.keys # => ["rar3", "rar5", "zip", ...]
    class FormatSpecLoader
      class << self
        # Load a format specification from a YAML file
        #
        # @param format_name [String] The name of the format (e.g., "rar5")
        # @param config_dir [String] The directory containing format specs
        # @return [FormatSpecification] The loaded format specification
        # @raise [FormatError] If the specification file is not found
        #   or invalid
        def load(format_name, config_dir: default_config_dir)
          spec_file = File.join(config_dir, "#{format_name}_spec.yml")

          unless File.exist?(spec_file)
            raise FormatError,
                  "Format specification not found: #{spec_file}"
          end

          yaml_content = File.read(spec_file)
          parsed_yaml = YAML.safe_load(
            yaml_content,
            permitted_classes: [Symbol],
            symbolize_names: true,
          )

          validate_spec(parsed_yaml, format_name)

          spec = FormatSpecification.new(parsed_yaml)
          register_spec(format_name, spec)
          spec
        rescue Psych::SyntaxError => e
          raise FormatError,
                "Invalid YAML in #{spec_file}: #{e.message}"
        end

        # Get all loaded format specifications
        #
        # @return [Hash<String, FormatSpecification>] All loaded specs
        def all_specs
          @all_specs ||= {}
        end

        # Clear all loaded specifications (primarily for testing)
        #
        # @return [void]
        def clear_specs
          @all_specs = {}
        end

        # Check if a format specification is loaded
        #
        # @param format_name [String] The format name
        # @return [Boolean] True if loaded, false otherwise
        def loaded?(format_name)
          all_specs.key?(format_name)
        end

        # Get a loaded specification
        #
        # @param format_name [String] The format name
        # @return [FormatSpecification, nil] The spec or nil if not loaded
        def get(format_name)
          all_specs[format_name]
        end

        # Load all format specifications from a directory
        #
        # @param config_dir [String] The directory containing format specs
        # @return [Hash<String, FormatSpecification>] All loaded specs
        def load_all(config_dir: default_config_dir)
          return all_specs unless Dir.exist?(config_dir)

          Dir.glob(File.join(config_dir, "*_spec.yml")).each do |spec_file|
            format_name = File.basename(spec_file, "_spec.yml")
            unless loaded?(format_name)
              load(format_name,
                   config_dir: config_dir)
            end
          end

          all_specs
        end

        private

        # Default configuration directory for format specifications
        #
        # @return [String] The default config directory path
        def default_config_dir
          File.join(__dir__, "../../../config/formats")
        end

        # Register a loaded specification
        #
        # @param format_name [String] The format name
        # @param spec [FormatSpecification] The specification to register
        # @return [void]
        def register_spec(format_name, spec)
          all_specs[format_name] = spec
        end

        # Validate a parsed YAML specification
        #
        # @param parsed_yaml [Hash] The parsed YAML content
        # @param format_name [String] The format name
        # @return [void]
        # @raise [FormatError] If the spec is invalid
        def validate_spec(parsed_yaml, format_name)
          unless parsed_yaml.is_a?(Hash) && parsed_yaml[:format]
            raise FormatError,
                  "Invalid format specification for #{format_name}: " \
                  "missing 'format' key"
          end

          format_data = parsed_yaml[:format]
          required_keys = %i[name version magic_bytes]

          required_keys.each do |key|
            next if format_data[key]

            raise FormatError,
                  "Invalid format specification for #{format_name}: " \
                  "missing required key '#{key}'"
          end
        end
      end
    end

    # Model class for encryption data
    class EncryptionData < Lutaml::Model::Serializable
      attribute :supported, :boolean
      attribute :algorithms, :string, collection: true
      attribute :key_derivation, :string
      attribute :kdf_iterations, :integer
      attribute :salt_size, :integer
    end

    # Model class for checksum data
    class ChecksumData < Lutaml::Model::Serializable
      attribute :algorithm, :string
      attribute :size, :integer
    end

    # Model class for format data
    class FormatData < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :version, :string
      attribute :extension, :string
      attribute :magic_bytes, :integer, collection: true
      attribute :block_types, :hash
      attribute :archive_flags, :hash
      attribute :main_header_flags, :hash
      attribute :file_header_flags, :hash
      attribute :file_flags, :hash
      attribute :encryption_flags, :hash
      attribute :compression_methods, :hash
      attribute :host_os, :hash
      attribute :dictionary_sizes, :hash
      attribute :encryption, EncryptionData
      attribute :checksum, ChecksumData
      attribute :features, :hash
      attribute :compression_features, :hash
      attribute :advanced_features, :hash
      attribute :extra_records, :hash
    end

    # Model class representing a format specification
    #
    # This class uses Lutaml::Model to provide a structured representation
    # of format specifications loaded from YAML files.
    class FormatSpecification < Lutaml::Model::Serializable
      attribute :format, FormatData

      # Get a value from the format specification
      #
      # @param key [Symbol, String] The key to retrieve
      # @return [Object] The value for the key
      def [](key)
        format.send(key)
      end

      # Get magic bytes as an array of integers
      #
      # @return [Array<Integer>] The magic bytes
      def magic_bytes
        format.magic_bytes
      end

      # Get the format name
      #
      # @return [String] The format name
      def name
        format.name
      end

      # Get the format version
      #
      # @return [String] The format version
      def version
        format.version
      end
    end
  end
end
