# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      module Decode
        extend T::Sig

        sig { params(required: T::Boolean, meta: Model::Meta).returns(T::Boolean) }
        def self.optional_nullable?(required:, meta:) = !required && meta.nullable && meta.default.nil?

        sig do
          params(source: String, key: String, schema: Model::Schema, required: T::Boolean,
                 registry: TypeRegistry).returns(String)
        end
        def self.expression(source:, key:, schema:, required:, registry:)
          meta = Model::Schema.meta(schema)
          inner = if Model::Schema.file?(schema)
                    "::OpenAPIKit::Decode.file(v)"
                  else
                    registry.from_wire_expr(schema, value: "v")
                  end
          quoted = key.inspect
          default = meta.default

          if default && !required
            fallback = Defaults.expression(schema: schema, default: default, registry: registry)
            return "::OpenAPIKit::Decode.defaulted(#{source}, #{quoted}, #{fallback}) { |v| #{inner} }"
          end

          return "::OpenAPIKit::Decode.optional_nullable(#{source}, #{quoted}) { |v| #{inner} }" if
            optional_nullable?(required: required, meta: meta)
          return "::OpenAPIKit::Decode.required_nullable(#{source}, #{quoted}) { |v| #{inner} }" if
            required && meta.nullable
          return "::OpenAPIKit::Decode.required(#{source}, #{quoted}) { |v| #{inner} }" if required

          "::OpenAPIKit::Decode.optional(#{source}, #{quoted}) { |v| #{inner} }"
        end
      end
    end
  end
end
