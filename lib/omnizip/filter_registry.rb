# frozen_string_literal: true

module Omnizip
  class FilterRegistry < Omnizip::Registry
    DEFAULT_FORMATS = %i[xz seven_zip].freeze

    BUILTIN_FILTERS = {
      :"bcj-x86" => "Omnizip::Filters::BcjX86",
      :"bcj-arm" => "Omnizip::Filters::BcjArm",
      :"bcj-arm64" => "Omnizip::Filters::BcjArm64",
      :"bcj-ia64" => "Omnizip::Filters::BcjIa64",
      :"bcj-ppc" => "Omnizip::Filters::BcjPpc",
      :"bcj-sparc" => "Omnizip::Filters::BcjSparc",
      :bcj => "Omnizip::Filters::BCJ",
      :bcj2 => "Omnizip::Filters::Bcj2",
      :delta => "Omnizip::Filters::Delta",
    }.freeze

    class << self
      def not_found_error_class
        Omnizip::UnknownFilterError
      end

      def label
        "Filter"
      end

      def register(name, filter_class, formats: DEFAULT_FORMATS)
        raise ArgumentError, "Filter name cannot be nil" if name.nil?
        raise ArgumentError, "Filter class cannot be nil" if filter_class.nil?

        synchronize do
          storage[normalize_key(name)] = {
            class: filter_class,
            formats: formats,
          }
        end
        filter_class
      end
      alias register_with_formats register

      def get(name)
        entry = entry_for(name)
        unless entry
          raise not_found_error_class,
                "#{label} not registered: #{name.inspect}. " \
                "Available: #{available.join(', ')}"
        end

        entry[:class]
      end

      def get_for_format(name, format)
        entry = entry_for(name)
        raise KeyError, "Filter not found: #{name}" unless entry

        unless entry[:formats].include?(format)
          raise ArgumentError,
                "Filter #{name} not supported for format #{format}"
        end

        entry[:class].new
      end

      def supports_format?(name, format)
        entry = entry_for(name)
        return false unless entry

        entry[:formats]&.include?(format)
      end

      def filters_for_format(format)
        # Ensure all lazy triggers have fired so the format filter list
        # reflects every registered builtin.
        lazy_triggers.keys.dup.each { |name| get(name) }

        storage.select { |_, info| info[:formats]&.include?(format) }.keys
      end

      private

      def entry_for(name)
        normalized = normalize_key(name)
        entry = storage[normalized]
        return entry if entry

        trigger = lazy_triggers[normalized]
        if trigger
          synchronize { lazy_triggers.delete(normalized) }
          trigger.call
          entry = storage[normalized]
          return entry if entry
        end

        nil
      end
    end
  end
end

# Lazy triggers — calling the Filters::Registry.register_all re-runs
# the registration of every builtin filter. Idempotent: register just
# overwrites the storage entry. Survives reset! because the trigger
# proc is held by FilterRegistry, not the storage.
Omnizip::FilterRegistry::BUILTIN_FILTERS.each_key do |name|
  Omnizip::FilterRegistry.register_lazy(name) do
    Omnizip::Filters::Registry.register_all
  end
end
