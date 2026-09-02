# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    class RubyType < T::Struct
      extend T::Sig

      CONSTANT_PATH = T.let(/\A(::)?[A-Z]\w*(::[A-Z]\w*)*\z/, Regexp)

      const :type, String
      const :codec, String

      sig { params(where: String, value: T.untyped).returns(RubyType) }
      def self.parse(where, value)
        unless value.is_a?(Hash)
          raise ConfigError,
                "#{where} must be a mapping with `type` and `codec`, got #{value.inspect}.\n  " \
                "#{where}:\n    type: \"::YourType\"\n    codec: \"YourApp::YourTypeCodec\""
        end

        unknown = value.keys.map(&:to_s) - %w[type codec]
        unless unknown.empty?
          raise ConfigError,
                "#{where} has unknown key#{"s" if unknown.size > 1} #{unknown.sort.join(", ")}. " \
                "Valid keys: type, codec."
        end

        missing = %w[type codec].reject { |key| value[key] }
        unless missing.empty?
          raise ConfigError,
                "#{where} is missing #{missing.join(" and ")}. Both are required: `type` is what " \
                "appears in signatures, `codec` is what converts it: a module extending, or an " \
                "instance of a class including, Oapi::Codec."
        end

        codec = value.fetch("codec").to_s
        unless codec.match?(CONSTANT_PATH)
          raise ConfigError,
                "#{where}.codec is #{codec.inspect}, which is not a Ruby constant path. " \
                "It must name a constant holding a codec, e.g. \"YourApp::YourTypeCodec\"."
        end

        new(type: value.fetch("type").to_s, codec: codec)
      end
    end
  end
end
