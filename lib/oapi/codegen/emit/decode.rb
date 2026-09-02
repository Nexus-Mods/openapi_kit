# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      module Decode
        extend T::Sig

        sig { params(required: T::Boolean, meta: Model::Meta).returns(T::Boolean) }
        def self.tristate?(required:, meta:) = !required && meta.nullable && meta.default.nil?

        sig do
          params(source: String, key: String, schema: Model::Schema, required: T::Boolean,
                 registry: TypeRegistry).returns(String)
        end
        def self.expression(source:, key:, schema:, required:, registry:)
          meta = Model::Schema.meta(schema)
          inner = registry.from_wire_expr(schema, value: "v")
          quoted = key.inspect
          default = meta.default

          if default && !required
            fallback = Defaults.expression(schema: schema, default: default, registry: registry)
            return "::Oapi::Decode.defaulted(#{source}, #{quoted}, #{fallback}) { |v| #{inner} }"
          end

          return "::Oapi::Decode.tristate(#{source}, #{quoted}) { |v| #{inner} }" if
            tristate?(required: required, meta: meta)
          return "::Oapi::Decode.nullable_field(#{source}, #{quoted}) { |v| #{inner} }" if required && meta.nullable
          return "::Oapi::Decode.field(#{source}, #{quoted}) { |v| #{inner} }" if required

          "::Oapi::Decode.optional(#{source}, #{quoted}) { |v| #{inner} }"
        end
      end
    end
  end
end
