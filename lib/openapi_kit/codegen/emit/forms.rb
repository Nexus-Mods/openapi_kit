# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class Forms
        extend T::Sig

        sig { params(registry: TypeRegistry).void }
        def initialize(registry:)
          @registry = registry
        end

        sig { params(buffer: Buffer, type: Model::FormDef).void }
        def emit(buffer, type)
          qualified = @registry.sorbet_type(Model::Ref.new(name: type.name))

          buffer.nest("module Form") do
            buffer.line("extend T::Sig")
            buffer.line("extend T::Generic")
            buffer.line("extend ::OpenAPIKit::Form::Contract")
            buffer.blank
            buffer.line("Value = type_template { { fixed: #{qualified} } }")
            buffer.blank
            buffer.line("sig { override.params(parts: ::OpenAPIKit::Form::Parts).returns(#{qualified}) }")
            buffer.nest("def self.from_parts(parts)") do
              buffer.line("#{qualified}.new(")
              buffer.indent do
                type.properties.each { |property| buffer.line("#{property.identifier}: #{decode(property)},") }
                extra = type.additional_properties
                buffer.line("additional_properties: #{decode_extra(type, extra)},") if extra
              end
              buffer.line(")")
            end
          end
        end

        private

        sig { params(property: Model::Property).returns(String) }
        def decode(property)
          Decode.expression(source: "parts", key: property.name, schema: property.schema,
                            required: property.required, registry: @registry)
        end

        sig { params(type: Model::FormDef, schema: Model::Schema).returns(String) }
        def decode_extra(type, schema)
          known = type.properties.map { |property| property.name.inspect }.join(", ")
          inner = @registry.from_wire_expr(schema, value: "item")
          "::OpenAPIKit::Decode.values(parts.except(#{known})) { |item| #{inner} }"
        end
      end
    end
  end
end
