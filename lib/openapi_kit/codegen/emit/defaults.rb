# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      module Defaults
        extend T::Sig

        sig do
          params(schema: Model::Schema, default: Model::Default, registry: TypeRegistry).returns(String)
        end
        def self.expression(schema:, default:, registry:)
          literal = default.value
          return "nil" if literal.nil?
          return literal.inspect if registry.literal_matches_type?(schema, literal)

          registry.from_wire_expr(schema, value: literal.inspect)
        end

        sig do
          params(schema: Model::Schema, default: Model::Default, registry: TypeRegistry).returns(String)
        end
        def self.clause(schema:, default:, registry:)
          literal = default.value
          return "default: nil" if literal.nil?
          return "default: #{literal.inspect}" if registry.literal_matches_type?(schema, literal)

          "factory: -> { #{expression(schema: schema, default: default, registry: registry)} }"
        end

        sig { params(required: T::Boolean, meta: Model::Meta).returns(T::Boolean) }
        def self.nilable?(required:, meta:)
          default = meta.default
          return true if default && default.value.nil?

          meta.nullable || (!required && default.nil?)
        end
      end
    end
  end
end
