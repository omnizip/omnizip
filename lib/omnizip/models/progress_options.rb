# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require "lutaml/model"

module Omnizip
  module Models
    # Model representing progress tracking options.
    #
    # This class encapsulates configuration for progress tracking,
    # including reporter type, update interval, and display preferences.
    class ProgressOptions < Lutaml::Model::Serializable
      attribute :reporter, :string, default: -> { "auto" }
      attribute :update_interval, :float, default: -> { 0.5 }
      attribute :show_rate, :boolean, default: -> { true }
      attribute :show_eta, :boolean, default: -> { true }
      attribute :show_files, :boolean, default: -> { true }
      attribute :show_bytes, :boolean, default: -> { true }

      json do
        map "reporter", to: :reporter
        map "update_interval", to: :update_interval
        map "show_rate", to: :show_rate
        map "show_eta", to: :show_eta
        map "show_files", to: :show_files
        map "show_bytes", to: :show_bytes
      end
    end
  end
end
