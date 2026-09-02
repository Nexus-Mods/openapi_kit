# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Types
        extend T::Sig

        sig { params(document: Ir::Document, registry: TypeRegistry, config: Config).void }
        def initialize(document:, registry:, config:)
          @document = document
          @registry = registry
          @config = config
          @codecs = T.let(Codecs.new(document: document, registry: registry, config: config), Codecs)
        end

        sig { returns(T::Array[SourceFile]) }
        def render
          declared_types.map do |type|
            name = Ir::TypeDef.name_of(type)
            Source.file(path: "#{@config.module_path}/types/#{Naming.snake(name)}.rb",
                        modules: @config.modules + ["Types"]) do |buffer|
              emit_declaration(buffer, type)
            end
          end
        end

        private

        sig { returns(T::Array[Ir::TypeDef]) }
        def declared_types = @document.types.grep_v(Ir::AliasDef)

        sig { params(buffer: Buffer, type: Ir::TypeDef).void }
        def emit_declaration(buffer, type)
          case type
          when Ir::EnumDef then emit_enum(buffer, type)
          when Ir::UnionDef then emit_union(buffer, type)
          when Ir::ObjectDef then emit_object(buffer, type)
          when Ir::AliasDef then nil
          else T.absurd(type)
          end
        end

        sig { params(buffer: Buffer, type: Ir::EnumDef).void }
        def emit_enum(buffer, type)
          buffer.nest("class #{type.name} < T::Enum") do
            buffer.nest("enums do") do
              type.members.each { |member| buffer.line("#{member.constant} = new(#{member.value.inspect})") }
            end
            buffer.blank
            @codecs.emit(buffer, type)
          end
        end

        sig { params(buffer: Buffer, type: Ir::UnionDef).void }
        def emit_union(buffer, type)
          members = type.members.map { |member| @registry.sorbet_type(member) }.uniq
          inner = members.one? ? T.must(members.first) : "T.any(#{members.join(", ")})"

          buffer.nest("module #{type.name}") do
            buffer.line("Value = T.type_alias { #{inner} }")
            buffer.blank
            @codecs.emit(buffer, type)
          end
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
            buffer.blank
            @codecs.emit(buffer, type)
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
          return "#{declaration}, factory: -> { ::Oapi::Absent.new }" if Decode.tristate?(required: property.required,
                                                                                          meta: Ir::Schema.meta(property.schema))

          declaration
        end

        sig { params(property: Ir::Property, default: Ir::Default).returns(String) }
        def default_clause(property, default)
          Defaults.clause(schema: property.schema, default: default, registry: @registry)
        end

        sig { params(property: Ir::Property).returns(String) }
        def prop_type(property)
          meta = Ir::Schema.meta(property.schema)
          base = @registry.sorbet_type(property.schema)
          if Decode.tristate?(required: property.required, meta: Ir::Schema.meta(property.schema))
            return "::Oapi::Optional[T.nilable(#{base})]"
          end
          return "T.nilable(#{base})" if Defaults.nilable?(required: property.required, meta: meta)

          base
        end
      end
    end
  end
end
