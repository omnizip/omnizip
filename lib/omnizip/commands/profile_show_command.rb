# frozen_string_literal: true

require_relative "../cli/output_formatter"

module Omnizip
  module Commands
    # Command to show details of a specific compression profile
    class ProfileShowCommand
      def initialize(options = {})
        @options = options
      end

      def run(profile_name)
        profile_sym = profile_name.to_sym
        profile = Omnizip::Profile.get(profile_sym)

        unless profile
          warn "Profile '#{profile_name}' not found"
          warn ""
          warn "Available profiles:"
          Omnizip::Profile.list.each { |name| warn "  - #{name}" }
          exit 1
        end

        display_profile(profile)
      end

      private

      def display_profile(profile)
        puts "Profile: #{profile.name}"
        puts "Algorithm:   #{profile.algorithm}"
        puts "Level:       #{profile.level}"
        puts "Filter:      #{profile.filter || "none"}"
        puts "Solid:       #{profile.solid}"
        puts "Description: #{profile.description}"

        return unless profile.respond_to?(:base_profile) && profile.base_profile

        puts "Based on:    #{profile.base_profile.name}"
      end
    end
  end
end
