# frozen_string_literal: true

require_relative "../cli/output_formatter"

module Omnizip
  module Commands
    # Command to list available compression profiles
    class ProfileListCommand
      def initialize(options = {})
        @options = options
      end

      def run
        profiles = Omnizip::Profile.registry.all.sort_by(&:name)

        if @options[:verbose]
          list_detailed(profiles)
        else
          list_simple(profiles)
        end
      end

      private

      def list_simple(profiles)
        puts "Available compression profiles:"
        puts ""

        profiles.each do |profile|
          default_marker = profile.name == :balanced ? " [default]" : ""
          puts format(
            "  %-12s - %s%s",
            profile.name,
            profile.description,
            default_marker
          )
        end
      end

      def list_detailed(profiles)
        puts "Available compression profiles:"
        puts ""

        profiles.each do |profile|
          puts "Profile: #{profile.name}"
          puts "  Algorithm:   #{profile.algorithm}"
          puts "  Level:       #{profile.level}"
          puts "  Filter:      #{profile.filter || "none"}"
          puts "  Solid:       #{profile.solid}"
          puts "  Description: #{profile.description}"
          puts ""
        end
      end
    end
  end
end
