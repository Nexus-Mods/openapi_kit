# typed: strict
# frozen_string_literal: true

module Oapi
  class RubyType < T::Struct
    extend T::Sig

    const :type, String
    const :coder, String

    sig { params(where: String, value: T.untyped).returns(RubyType) }
    def self.parse(where, value)
      unless value.is_a?(Hash)
        raise ConfigError,
              "#{where} must be a mapping with `type` and `coder`, got #{value.inspect}.\n  " \
              "#{where}:\n    type: \"::YourType\"\n    coder: \"YourApp::YourTypeCoder\""
      end

      unknown = value.keys.map(&:to_s) - %w[type coder]
      unless unknown.empty?
        raise ConfigError,
              "#{where} has unknown key#{"s" if unknown.size > 1} #{unknown.sort.join(", ")}. " \
              "Valid keys: type, coder."
      end

      missing = %w[type coder].reject { |key| value[key] }
      unless missing.empty?
        raise ConfigError,
              "#{where} is missing #{missing.join(" and ")}. Both are required: `type` is what " \
              "appears in signatures, `coder` is the module extending Oapi::Coder that converts it."
      end

      new(type: value.fetch("type").to_s, coder: value.fetch("coder").to_s)
    end
  end
end
