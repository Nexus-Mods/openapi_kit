# typed: strict
# frozen_string_literal: true

module Oapi
  class Error < StandardError; end

  class ConfigError < Error; end

  class SchemaError < Error; end
end
