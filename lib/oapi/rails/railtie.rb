# typed: strict
# frozen_string_literal: true

require "rails"

require "oapi/rails"

module Oapi
  module Rails
    class Railtie < ::Rails::Railtie
      config.to_prepare do
        Oapi::Rails.verify! unless Oapi::Rails.apis.empty?
      end
    end
  end
end
