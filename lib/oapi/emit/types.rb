# typed: strict
# frozen_string_literal: true

module Oapi
  module Emit
    class Types
      extend T::Sig

      sig { params(document: Ir::Document, registry: TypeRegistry, config: Config).void }
      def initialize(document:, registry:, config:)
        @document = document
        @registry = registry
        @config = config
      end

      sig { returns(String) }
      def render
        buffer = Buffer.new
        buffer.line("# typed: strict")
        buffer.line("# frozen_string_literal: true")
        buffer.blank
        buffer.nest_modules(@config.modules) do
          buffer.nest_modules(["Types"]) { emit_types(buffer) }
          buffer.blank
          buffer.nest_modules(["Codecs"]) { emit_codecs(buffer) }
        end
        buffer.to_s
      end

      private

      sig { params(buffer: Buffer).void }
      def emit_types(buffer)
        ordered_types.each_with_index do |type, index|
          buffer.blank if index.positive?
          case type
          when Ir::EnumDef then emit_enum(buffer, type)
          when Ir::UnionDef then emit_union(buffer, type)
          when Ir::ObjectDef then emit_object(buffer, type)
          when Ir::AliasDef then nil
          else T.absurd(type)
          end
        end
      end

      sig { returns(T::Array[Ir::TypeDef]) }
      def ordered_types
        remaining = @document.types.grep_v(Ir::AliasDef)
        by_name = remaining.to_h { |type| [Ir::TypeDef.name_of(type), type] }
        ordered = T.let([], T::Array[Ir::TypeDef])
        placed = T.let(Set.new, T::Set[String])
        path = T.let([], T::Array[String])

        visit = T.let(nil, T.untyped)
        visit = lambda do |type|
          name = Ir::TypeDef.name_of(type)
          next if placed.include?(name)

          raise SchemaError, cycle_message(path.drop(path.index(name).to_i) + [name]) if path.include?(name)

          path.push(name)
          dependencies(type).each do |dependency|
            next if dependency == name

            found = by_name[dependency]
            visit.call(found) if found
          end
          path.pop
          placed << name
          ordered << type
          nil
        end

        remaining.each { |type| visit.call(type) }
        ordered
      end

      sig { params(names: T::Array[String]).returns(String) }
      def cycle_message(names)
        <<~MESSAGE.strip
          #{names.join(" -> ")} form a cycle of mutually referencing schemas.

          Sorbet evaluates a T::Struct property type when the class body runs, so two
          schemas cannot reference each other directly. A schema referring to itself is
          fine. Break the cycle by referring to one side by id, or by extracting the
          shared part into a third schema.
        MESSAGE
      end

      sig { params(type: Ir::TypeDef).returns(T::Array[String]) }
      def dependencies(type)
        schemas =
          case type
          when Ir::ObjectDef then type.properties.map(&:schema) + [type.additional_properties].compact
          when Ir::UnionDef then type.members
          when Ir::AliasDef then [type.target]
          when Ir::EnumDef then []
          else T.absurd(type)
          end

        schemas.flat_map { |schema| referenced_names(schema) }.uniq
      end

      sig { params(schema: Ir::Schema).returns(T::Array[String]) }
      def referenced_names(schema)
        case schema
        when Ir::Ref then [schema.name]
        when Ir::List then referenced_names(schema.items)
        when Ir::Freeform then schema.values ? referenced_names(T.must(schema.values)) : []
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema, Ir::Untyped then []
        else T.absurd(schema)
        end
      end

      sig { params(buffer: Buffer, type: Ir::EnumDef).void }
      def emit_enum(buffer, type)
        buffer.nest("class #{type.name} < T::Enum") do
          buffer.nest("enums do") do
            type.members.each { |member| buffer.line("#{member.constant} = new(#{member.value.inspect})") }
          end
        end
      end

      sig { params(buffer: Buffer, type: Ir::UnionDef).void }
      def emit_union(buffer, type)
        members = type.members.map { |member| @registry.sorbet_type(member) }.uniq
        inner = members.one? ? T.must(members.first) : "T.any(#{members.join(", ")})"
        buffer.line("#{type.name} = T.type_alias { #{inner} }")
      end

      sig { params(buffer: Buffer, type: Ir::ObjectDef).void }
      def emit_object(buffer, type)
        buffer.nest("class #{type.name} < T::Struct") do
          buffer.line("extend T::Sig")
          buffer.blank
          type.properties.each { |property| buffer.line(prop_line(property)) }
          extra = type.additional_properties
          buffer.line("const :additional_properties, #{additional_type(extra)}, factory: -> { {} }") if extra
          buffer.blank
          emit_equality(buffer, type)
        end
      end

      sig { params(buffer: Buffer, type: Ir::ObjectDef).void }
      def emit_equality(buffer, type)
        buffer.line("sig { params(other: T.untyped).returns(T::Boolean) }")
        buffer.line("def ==(other) = other.instance_of?(#{type.name}) && other.serialize == serialize")
        buffer.blank
        buffer.line("sig { params(other: T.untyped).returns(T::Boolean) }")
        buffer.line("def eql?(other) = self == other")
        buffer.blank
        buffer.line("sig { returns(::Integer) }")
        buffer.line("def hash = [self.class, serialize].hash")
      end

      sig { params(schema: Ir::Schema).returns(String) }
      def additional_type(schema) = "T::Hash[::String, #{@registry.sorbet_type(schema)}]"

      sig { params(property: Ir::Property).returns(String) }
      def prop_line(property)
        meta = Ir::Schema.meta(property.schema)
        declaration = "const :#{property.identifier}, #{prop_type(property)}"

        default = meta.default
        return "#{declaration}, #{default_clause(property, default)}" if default && !property.required
        return "#{declaration}, factory: -> { ::Oapi::Absent.new }" if tristate?(property)

        declaration
      end

      sig { params(property: Ir::Property, default: Ir::Default).returns(String) }
      def default_clause(property, default)
        literal = default.value
        return "default: #{literal.inspect}" if literal.is_a?(::String) || literal.is_a?(::Integer) ||
                                                literal.is_a?(::Float) || literal == true || literal == false

        "factory: -> { #{@registry.from_wire_expr(property.schema, value: literal.inspect)} }"
      end

      sig { params(property: Ir::Property).returns(T::Boolean) }
      def tristate?(property)
        meta = Ir::Schema.meta(property.schema)
        !property.required && meta.nullable && meta.default.nil?
      end

      sig { params(property: Ir::Property).returns(String) }
      def prop_type(property)
        meta = Ir::Schema.meta(property.schema)
        base = @registry.sorbet_type(property.schema)
        return "::Oapi::Optional[T.nilable(#{base})]" if tristate?(property)
        return "T.nilable(#{base})" if meta.nullable || (!property.required && meta.default.nil?)

        base
      end

      sig { params(buffer: Buffer).void }
      def emit_codecs(buffer)
        entries = ordered_types
        entries.each_with_index do |type, index|
          buffer.blank if index.positive?
          emit_codec(buffer, type)
        end
      end

      sig { params(buffer: Buffer, type: Ir::TypeDef).void }
      def emit_codec(buffer, type)
        name = Ir::TypeDef.name_of(type)
        buffer.nest("class #{name}Codec") do
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
        buffer.line("#{name} = T.let(#{name}Codec.new, #{name}Codec)")
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
      def qualified(name) = "#{@config.namespace}::Types::#{name}"

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

      sig { params(property: Ir::Property).returns(String) }
      def decode_expr(property)
        meta = Ir::Schema.meta(property.schema)
        inner = @registry.from_wire_expr(property.schema, value: "v")
        key = property.name.inspect
        default = meta.default

        return "::Oapi::Decode.defaulted(raw, #{key}, #{default.value.inspect}) { |v| #{inner} }" if
          default && !property.required
        return "::Oapi::Decode.tristate(raw, #{key}) { |v| #{inner} }" if tristate?(property)
        return "::Oapi::Decode.nullable_field(raw, #{key}) { |v| #{inner} }" if property.required && meta.nullable
        return "::Oapi::Decode.field(raw, #{key}) { |v| #{inner} }" if property.required

        "::Oapi::Decode.optional(raw, #{key}) { |v| #{inner} }"
      end

      sig { params(buffer: Buffer, type: Ir::ObjectDef).void }
      def emit_object_to_wire(buffer, type)
        buffer.nest("def to_wire(value)") do
          buffer.line("wire = T.let({}, T::Hash[::String, ::Oapi::Wire])")
          type.properties.each { |property| emit_property_to_wire(buffer, property) }
          buffer.line("wire.merge!(value.additional_properties)") if type.additional_properties
          buffer.line("wire")
        end
      end

      sig { params(buffer: Buffer, property: Ir::Property).void }
      def emit_property_to_wire(buffer, property)
        meta = Ir::Schema.meta(property.schema)
        key = property.name.inspect
        reader = property.identifier.to_s

        if tristate?(property)
          buffer.line("#{reader} = value.#{reader}")
          buffer.nest("if #{reader}.is_a?(::Oapi::Present)") do
            buffer.line("inner = #{reader}.value")
            buffer.line("wire[#{key}] = inner.nil? ? nil : #{@registry.to_wire_expr(property.schema, value: "inner")}")
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
      def codec_for(name) = "#{@config.namespace}::Codecs::#{name}"
    end
  end
end
