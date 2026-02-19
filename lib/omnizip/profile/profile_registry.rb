# frozen_string_literal: true

module Omnizip
  module Profile
    # Thread-safe registry for compression profiles
    #
    # This class manages both built-in and custom compression profiles,
    # providing a central location for profile registration, lookup, and
    # management.
    class ProfileRegistry
      # Initialize a new profile registry
      def initialize
        @profiles = {}
        @mutex = Mutex.new
      end

      # Register a profile
      #
      # @param profile [CompressionProfile] Profile to register
      # @raise [ArgumentError] if profile with same name already exists
      # @return [CompressionProfile] The registered profile
      def register(profile)
        unless profile.is_a?(CompressionProfile)
          raise ArgumentError,
                "Profile must be a CompressionProfile instance"
        end

        @mutex.synchronize do
          if @profiles.key?(profile.name)
            raise ArgumentError,
                  "Profile '#{profile.name}' is already registered"
          end

          @profiles[profile.name] = profile
        end

        profile
      end

      # Register a profile, replacing if it exists
      #
      # @param profile [CompressionProfile] Profile to register
      # @return [CompressionProfile] The registered profile
      def register!(profile)
        unless profile.is_a?(CompressionProfile)
          raise ArgumentError,
                "Profile must be a CompressionProfile instance"
        end

        @mutex.synchronize do
          @profiles[profile.name] = profile
        end

        profile
      end

      # Unregister a profile by name
      #
      # @param name [Symbol] Profile name
      # @return [CompressionProfile, nil] The unregistered profile or nil
      def unregister(name)
        @mutex.synchronize do
          @profiles.delete(name)
        end
      end

      # Get a profile by name
      #
      # @param name [Symbol] Profile name
      # @return [CompressionProfile, nil] Profile or nil if not found
      def get(name)
        @mutex.synchronize do
          @profiles[name]
        end
      end

      # Check if a profile is registered
      #
      # @param name [Symbol] Profile name
      # @return [Boolean] true if profile exists
      def registered?(name)
        @mutex.synchronize do
          @profiles.key?(name)
        end
      end

      # Get all registered profile names
      #
      # @return [Array<Symbol>] List of profile names
      def names
        @mutex.synchronize do
          @profiles.keys
        end
      end

      # Get all registered profiles
      #
      # @return [Array<CompressionProfile>] List of profiles
      def all
        @mutex.synchronize do
          @profiles.values
        end
      end

      # Find profiles suitable for a MIME type
      #
      # @param mime_type [String] MIME type string
      # @return [Array<CompressionProfile>] Suitable profiles
      def suitable_for(mime_type)
        all.select { |profile| profile.suitable_for?(mime_type) }
      end

      # Clear all registered profiles
      #
      # @return [void]
      def clear
        @mutex.synchronize do
          @profiles.clear
        end
      end

      # Get the number of registered profiles
      #
      # @return [Integer] Profile count
      def count
        @mutex.synchronize do
          @profiles.size
        end
      end

      # Iterate over all profiles
      #
      # @yield [profile] Yields each profile
      # @yieldparam profile [CompressionProfile] A registered profile
      # @return [void]
      # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- Ruby 3.0 compatibility
      def each(&block)
        all.each(&block)
      end
      # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

      # Get profile information as hash
      #
      # @return [Hash{Symbol => Hash}] Profiles indexed by name
      def to_h
        @mutex.synchronize do
          @profiles.transform_values(&:to_h)
        end
      end

      # String representation
      #
      # @return [String]
      def inspect
        @mutex.synchronize do
          "#<#{self.class.name} profiles=#{@profiles.keys.join(', ')}>"
        end
      end
    end
  end
end
