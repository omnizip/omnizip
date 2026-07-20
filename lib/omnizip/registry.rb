# frozen_string_literal: true

module Omnizip
  # Generic, thread-safe registry base class.
  #
  # Subclasses override the hooks +#not_found_error_class+,
  # +#normalize_key+, and +#label+ to specialize behavior. They may also
  # override +#register+ / +#get+ to add domain-specific arguments
  # (e.g., +#register_with_formats+ on FilterRegistry).
  #
  # The base class is intentionally minimal: it owns a Hash store and a
  # Mutex, and exposes the canonical CRUD quintet (+register+, +get+,
  # +registered?+, +available+, +reset!+). Backward-compat aliases are
  # provided so existing call sites keep working.
  class Registry
    class << self
      def not_found_error_class
        Omnizip::Error
      end

      def normalize_key(key)
        key.to_sym
      end

      def label
        return "Item" unless name

        name.gsub(/^Omnizip::/, "")
      end

      def register(key, value)
        synchronize { storage[normalize_key(key)] = value }
        value
      end

      # Register a lazy trigger for +key+. When +get(key)+ is called and
      # the key isn't yet in storage, the block is invoked. The block is
      # expected to trigger autoload of the implementation file (e.g., by
      # referencing a constant), which then self-registers.
      def register_lazy(key, &trigger)
        lazy_triggers[normalize_key(key)] = trigger
      end

      def get(key)
        normalized = normalize_key(key)
        value = storage[normalized]
        return value if value

        trigger = lazy_triggers[normalized]
        if trigger
          synchronize { lazy_triggers.delete(normalized) }
          trigger.call
          value = storage[normalized]
          return value if value
        end

        raise not_found_error_class,
              "#{label} not registered: #{key.inspect}. " \
              "Available: #{available.join(', ')}"
      end

      def registered?(key)
        storage.key?(normalize_key(key))
      end

      def available
        storage.keys
      end
      alias all available
      alias strategies available

      def reset!
        synchronize do
          storage.clear
          lazy_triggers.clear
        end
      end
      alias clear reset!
      alias clear! reset!
      alias reset reset!

      def entries
        synchronize { storage.dup }
      end

      def each(&block)
        return to_enum(:each) unless block

        entries.each(&block)
      end

      private

      def storage
        @storage ||= {}
      end

      def lazy_triggers
        @lazy_triggers ||= {}
      end

      def synchronize(&block)
        mutex.synchronize(&block)
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
