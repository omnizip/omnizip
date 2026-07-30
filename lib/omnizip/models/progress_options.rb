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
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    #
    # +render_nil+ is deliberately absent: the previous +to_h+ ended in
    # +.compact+, so an explicitly-nil value was dropped. +render_default+
    # alone keeps that nil-dropping behaviour.
    class ProgressOptions < Lutaml::Model::Serializable
      attribute :reporter, :string, default: "auto"
      attribute :update_interval, :float, default: 0.5
      attribute :show_rate, :boolean, default: true
      attribute :show_eta, :boolean, default: true
      attribute :show_files, :boolean, default: true
      attribute :show_bytes, :boolean, default: true

      key_value do
        map "reporter", to: :reporter, render_default: true
        map "update_interval", to: :update_interval, render_default: true
        map "show_rate", to: :show_rate, render_default: true
        map "show_eta", to: :show_eta, render_default: true
        map "show_files", to: :show_files, render_default: true
        map "show_bytes", to: :show_bytes, render_default: true
      end
    end
  end
end
