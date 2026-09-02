# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Codecs
        extend T::Sig

        sig { params(document: Ir::Document, registry: TypeRegistry, config: Config).void }
        def initialize(document:, registry:, config:)
          @document = document
          @registry = registry
          @config = config
        end

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit(buffer, type) = emit_codec(buffer, type)

        private

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit_codec(buffer, type)
          name = Ir::TypeDef.name_of(type)
          buffer.nest("class Codec") do
            buffer.line("extend T::Sig")
            buffer.line("extend T::Generic")
            buffer.line("include ::Oapi::Codec")
            buffer.blank
            buffer.line("Value = type_member { { fixed: #{qualified(name)} } }")
            buffer.blank
            emit_codec_constants(buffer, type)
            buffer.line("sig { override.params(value: T.untyped).returns(#{qualified(name)}) }")
            emit_from_wire(buffer, type)
            buffer.blank
            buffer.line("sig { override.params(value: #{qualified(name)}).returns(::Oapi::Wire) }")
            emit_to_wire(buffer, type)
          end
          buffer.blank
          buffer.line("CODEC = T.let(Codec.new, Codec)")
        end

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit_codec_constants(buffer, type)
          if type.is_a?(Ir::EnumDef)
            values = type.members.map { |member| member.value.inspect }.join(", ")
            buffer.line("VALUES = T.let([#{values}].freeze, T::Array[::Oapi::Wire])")
            buffer.blank
          end

          tag = type.is_a?(Ir::UnionDef) ? type.tag : nil
          return unless tag.is_a?(Ir::Tagged)

          tags = tag.mapping.keys.map(&:inspect).join(", ")
          buffer.line("TAGS = T.let([#{tags}].freeze, T::Array[::String])")
          buffer.blank
        end

        sig { params(name: String).returns(String) }
        def qualified(name) = @registry.sorbet_type(Ir::Ref.new(name: name))

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit_from_wire(buffer, type)
          case type
          when Ir::EnumDef then emit_enum_from_wire(buffer, type)
          when Ir::ObjectDef then emit_object_from_wire(buffer, type)
          when Ir::UnionDef then emit_union_from_wire(buffer, type)
          when Ir::AliasDef
            buffer.line("def from_wire(value) = #{@registry.from_wire_expr(type.target, value: "value")}")
          else T.absurd(type)
          end
        end

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit_to_wire(buffer, type)
          case type
          when Ir::EnumDef then buffer.line("def to_wire(value) = value.serialize")
          when Ir::ObjectDef then emit_object_to_wire(buffer, type)
          when Ir::UnionDef then emit_union_to_wire(buffer, type)
          when Ir::AliasDef
            buffer.line("def to_wire(value) = #{@registry.to_wire_expr(type.target, value: "value")}")
          else T.absurd(type)
          end
        end

        sig { params(buffer: Buffer, type: Ir::EnumDef).void }
        def emit_enum_from_wire(buffer, type)
          buffer.nest("def from_wire(value)") do
            buffer.line("#{qualified(type.name)}.try_deserialize(value) ||")
            message = Literal.string("expected one of ", Literal.expr(%(VALUES.join(", "))),
                                     ", got ", Literal.expr("value.inspect"))
            buffer.indent { buffer.line("raise(::Oapi::DecodeError.new(#{message}))") }
          end
        end

        sig { params(buffer: Buffer, type: Ir::ObjectDef).void }
        def emit_object_from_wire(buffer, type)
          buffer.nest("def from_wire(value)") do
            buffer.line("raw = ::Oapi::Decode.object(value)")
            buffer.line("#{qualified(type.name)}.new(")
            buffer.indent do
              type.properties.each { |property| buffer.line("#{property.identifier}: #{decode_expr(property)},") }
              extra = type.additional_properties
              buffer.line("additional_properties: #{additional_decode(type, extra)},") if extra
            end
            buffer.line(")")
          end
        end

        sig { params(type: Ir::ObjectDef, schema: Ir::Schema).returns(String) }
        def additional_decode(type, schema)
          known = type.properties.map { |property| property.name.inspect }.join(", ")
          inner = @registry.from_wire_expr(schema, value: "item")
          "::Oapi::Decode.values(raw.except(#{known})) { |item| #{inner} }"
        end

        sig { params(schema: Ir::Schema).returns(String) }
        def additional_encode(schema)
          inner = @registry.to_wire_expr(schema, value: "item")
          return "value.additional_properties" if inner == "item"

          "value.additional_properties.transform_values { |item| #{inner} }"
        end

        sig { params(property: Ir::Property).returns(String) }
        def decode_expr(property)
          Decode.expression(source: "raw", key: property.name, schema: property.schema,
                            required: property.required, registry: @registry)
        end

        sig { params(buffer: Buffer, type: Ir::ObjectDef).void }
        def emit_object_to_wire(buffer, type)
          buffer.nest("def to_wire(value)") do
            buffer.line("wire = T.let({}, T::Hash[::String, ::Oapi::Wire])")
            type.properties.each { |property| emit_property_to_wire(buffer, property) }
            extra = type.additional_properties
            buffer.line("wire.merge!(#{additional_encode(extra)})") if extra
            buffer.line("wire")
          end
        end

        sig { params(buffer: Buffer, property: Ir::Property).void }
        def emit_property_to_wire(buffer, property)
          meta = Ir::Schema.meta(property.schema)
          key = property.name.inspect
          reader = property.identifier.to_s

          if Decode.tristate?(required: property.required, meta: Ir::Schema.meta(property.schema))
            buffer.line("#{reader} = value.#{reader}")
            buffer.nest("if #{reader}.is_a?(::Oapi::Present)") do
              buffer.line("inner = #{reader}.value")
              buffer.line("wire[#{key}] = inner.nil? ? nil : #{@registry.to_wire_expr(property.schema,
                                                                                      value: "inner")}")
            end
            return
          end

          if property.required && !meta.nullable
            buffer.line("wire[#{key}] = #{@registry.to_wire_expr(property.schema, value: "value.#{reader}")}")
            return
          end

          buffer.line("#{reader} = value.#{reader}")
          dumped = @registry.to_wire_expr(property.schema, value: reader)

          if property.required
            buffer.line("wire[#{key}] = #{reader}.nil? ? nil : #{dumped}")
          else
            buffer.line("wire[#{key}] = #{dumped} unless #{reader}.nil?")
          end
        end

        sig { params(buffer: Buffer, type: Ir::UnionDef).void }
        def emit_union_from_wire(buffer, type)
          tag = type.tag
          buffer.nest("def from_wire(value)") do
            case tag
            when Ir::Tagged then emit_tagged_from_wire(buffer, tag)
            when Ir::Untagged then emit_untagged_from_wire(buffer, type)
            else T.absurd(tag)
            end
          end
        end

        sig { params(buffer: Buffer, tag: Ir::Tagged).void }
        def emit_tagged_from_wire(buffer, tag)
          buffer.line("raw = ::Oapi::Decode.object(value)")
          buffer.line("tag = raw[#{tag.property_name.inspect}]")
          buffer.case_of("tag") do
            tag.mapping.each do |wire_value, name|
              buffer.line("when #{wire_value.inspect} then #{codec_for(name)}.from_wire(raw)")
            end
            message = Literal.string("expected #{tag.property_name} to be one of ",
                                     Literal.expr(%(TAGS.join(", "))), ", got ", Literal.expr("tag.inspect"))
            buffer.line("else raise(::Oapi::DecodeError.new(#{message}))")
          end
        end

        sig { params(buffer: Buffer, type: Ir::UnionDef).void }
        def emit_untagged_from_wire(buffer, type)
          buffer.line("::Oapi::Decode.first_of(value, #{type.name.inspect}, [")
          buffer.indent do
            type.members.each do |member|
              buffer.line("->(candidate) { #{@registry.from_wire_expr(member, value: "candidate")} },")
            end
          end
          buffer.line("])")
        end

        sig { params(buffer: Buffer, type: Ir::UnionDef).void }
        def emit_union_to_wire(buffer, type)
          buffer.nest("def to_wire(value)") do
            buffer.case_of("value") do
              type.members.each do |member|
                buffer.line("when #{@registry.sorbet_type(member)} then " \
                            "#{@registry.to_wire_expr(member, value: "value")}")
              end
              buffer.line("else T.absurd(value)")
            end
          end
        end

        sig { params(name: String).returns(String) }
        def codec_for(name) = "#{@config.namespace}::Types::#{name}::CODEC"
      end
    end
  end
end
