# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class Types
        extend T::Sig
        include Emitter

        sig { params(document: Model::Document, registry: TypeRegistry, config: Config).void }
        def initialize(document:, registry:, config:)
          @document = document
          @registry = registry
          @config = config
          @codecs = T.let(Codecs.new(document: document, registry: registry, config: config), Codecs)
          @forms = T.let(Forms.new(registry: registry), Forms)
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          declared_types.map do |type|
            name = Model::TypeDef.name_of(type)
            Source.file(path: "types/#{Naming.snake(name)}.rb",
                        modules: @config.modules + ["Types"]) do |buffer|
              emit_declaration(buffer, type)
            end
          end
        end

        private

        sig { returns(T::Array[Model::TypeDef]) }
        def declared_types = @document.types.grep_v(Model::AliasDef)

        sig { params(buffer: Buffer, type: Model::TypeDef).void }
        def emit_declaration(buffer, type)
          case type
          when Model::EnumDef then emit_enum(buffer, type)
          when Model::UnionDef then emit_union(buffer, type)
          when Model::ObjectDef then emit_object(buffer, type)
          when Model::FormDef then emit_form(buffer, type)
          when Model::AliasDef then nil
          else T.absurd(type)
          end
        end

        sig { params(buffer: Buffer, type: Model::EnumDef).void }
        def emit_enum(buffer, type)
          buffer.nest("class #{type.name} < T::Enum") do
            buffer.nest("enums do") do
              type.members.each { |member| buffer.line("#{member.constant} = new(#{member.value.inspect})") }
            end
            buffer.blank
            @codecs.emit(buffer, type)
          end
        end

        sig { params(buffer: Buffer, type: Model::UnionDef).void }
        def emit_union(buffer, type)
          members = type.members.map { |member| @registry.sorbet_type(member) }.uniq
          inner = members.one? ? T.must(members.first) : "T.any(#{members.join(", ")})"

          buffer.nest("module #{type.name}") do
            buffer.line("Value = T.type_alias { #{inner} }")
            buffer.blank
            @codecs.emit(buffer, type)
          end
        end

        sig { params(buffer: Buffer, type: Model::ObjectDef).void }
        def emit_object(buffer, type)
          buffer.nest("class #{type.name} < T::Struct") do
            buffer.line("extend T::Sig")
            buffer.blank
            type.properties.each { |property| buffer.line(prop_line(property)) }
            extra = type.additional_properties
            buffer.line("const :additional_properties, #{additional_type(extra)}, factory: -> { {} }") if extra
            buffer.blank
            emit_equality(buffer, type.name)
            buffer.blank
            @codecs.emit(buffer, type)
          end
        end

        sig { params(buffer: Buffer, type: Model::FormDef).void }
        def emit_form(buffer, type)
          buffer.nest("class #{type.name} < T::Struct") do
            buffer.line("extend T::Sig")
            buffer.blank
            type.properties.each { |property| buffer.line(prop_line(property)) }
            extra = type.additional_properties
            buffer.line("const :additional_properties, #{additional_type(extra)}, factory: -> { {} }") if extra
            buffer.blank
            emit_equality(buffer, type.name)
            buffer.blank
            @forms.emit(buffer, type)
          end
        end

        sig { params(buffer: Buffer, name: String).void }
        def emit_equality(buffer, name)
          buffer.line("sig { params(other: T.untyped).returns(T::Boolean) }")
          buffer.line("def ==(other) = other.instance_of?(#{name}) && other.serialize == serialize")
          buffer.blank
          buffer.line("sig { params(other: T.untyped).returns(T::Boolean) }")
          buffer.line("def eql?(other) = self == other")
          buffer.blank
          buffer.line("sig { returns(::Integer) }")
          buffer.line("def hash = [self.class, serialize].hash")
        end

        sig { params(schema: Model::Schema).returns(String) }
        def additional_type(schema) = "T::Hash[::String, #{@registry.sorbet_type(schema)}]"

        sig { params(property: Model::Property).returns(String) }
        def prop_line(property)
          meta = Model::Schema.meta(property.schema)
          declaration = "const :#{property.identifier}, #{prop_type(property)}"
          default = meta.default

          if default && !property.required
            clause = Defaults.clause(schema: property.schema, default: default, registry: @registry)
            return "#{declaration}, #{clause}"
          end
          return "#{declaration}, default: ::OpenAPIKit::ABSENT" if optional_nullable?(property)

          declaration
        end

        sig { params(property: Model::Property).returns(String) }
        def prop_type(property)
          meta = Model::Schema.meta(property.schema)
          base = if Model::Schema.file?(property.schema)
                   TypeRegistry::UPLOADED_FILE
                 else
                   @registry.sorbet_type(property.schema)
                 end

          return "::OpenAPIKit::Optional[T.nilable(#{base})]" if optional_nullable?(property)
          return "T.nilable(#{base})" if Defaults.nilable?(required: property.required, meta: meta)

          base
        end

        sig { params(property: Model::Property).returns(T::Boolean) }
        def optional_nullable?(property)
          Decode.optional_nullable?(required: property.required, meta: Model::Schema.meta(property.schema))
        end
      end
    end
  end
end
