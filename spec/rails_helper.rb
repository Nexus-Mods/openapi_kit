# frozen_string_literal: true

require "spec_helper"

require "rack/test"

require_relative "dummy/generate"
Dummy::Generate.call

require_relative "dummy/config/environment"

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.define_derived_metadata(file_path: %r{/spec/generated/rails_}) { |meta| meta[:type] = :request }
end
