# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    class TypeRegistry
      extend T::Sig

      sig { params(type: String, codec: T::Module[T.anything]).returns(RubyType) }
      def self.primitive(type, codec) = RubyType.for_codec(type: type, codec: codec)

      DEFAULT_TYPE_MAPPINGS = T.let(
        {
          "string" => primitive("::String", Oapi::Codec::String),
          "integer" => primitive("::Integer", Oapi::Codec::Integer),
          "number" => primitive("::Float", Oapi::Codec::Float),
          "boolean" => primitive("T::Boolean", Oapi::Codec::Boolean),

          "string:date-time" => primitive("::Time", Oapi::Codec::DateTime),
          "string:date" => primitive("::Date", Oapi::Codec::Date),
          "string:uuid" => primitive("::String", Oapi::Codec::Uuid),
          "string:byte" => primitive("::String", Oapi::Codec::Byte),
          "string:decimal" => primitive("::BigDecimal", Oapi::Codec::Decimal),
          "string:binary" => primitive("::ActionDispatch::Http::UploadedFile",
                                       Oapi::Codec::UploadedFile),

          "string:time" => primitive("::String", Oapi::Codec::String),
          "string:duration" => primitive("::String", Oapi::Codec::String),
          "string:email" => primitive("::String", Oapi::Codec::String),
          "string:idn-email" => primitive("::String", Oapi::Codec::String),
          "string:hostname" => primitive("::String", Oapi::Codec::String),
          "string:idn-hostname" => primitive("::String", Oapi::Codec::String),
          "string:ipv4" => primitive("::String", Oapi::Codec::String),
          "string:ipv6" => primitive("::String", Oapi::Codec::String),
          "string:uri" => primitive("::String", Oapi::Codec::String),
          "string:uri-reference" => primitive("::String", Oapi::Codec::String),
          "string:uri-template" => primitive("::String", Oapi::Codec::String),
          "string:iri" => primitive("::String", Oapi::Codec::String),
          "string:json-pointer" => primitive("::String", Oapi::Codec::String),
          "string:relative-json-pointer" => primitive("::String", Oapi::Codec::String),
          "string:regex" => primitive("::String", Oapi::Codec::String),
          "string:password" => primitive("::String", Oapi::Codec::String),

          "integer:int32" => primitive("::Integer", Oapi::Codec::Integer),
          "integer:int64" => primitive("::Integer", Oapi::Codec::Integer),

          "number:float" => primitive("::Float", Oapi::Codec::Float),
          "number:double" => primitive("::Float", Oapi::Codec::Float),
          "number:decimal" => primitive("::BigDecimal", Oapi::Codec::Decimal)
        }.freeze,
        T::Hash[String, RubyType]
      )

      sig { params(document: Model::Document, config: Config).returns(TypeRegistry) }
      def self.for(document, config)
        registry = new(
          namespace: config.namespace,
          type_mappings: DEFAULT_TYPE_MAPPINGS.merge(config.type_mappings),
          types: document.types.to_h { |type| [Model::TypeDef.name_of(type), type] }
        )

        registry.reject_alias_cycles!
        registry
      end

      # An alias contributes no constant of its own: every reference to it expands to its
      # target. A loop of them therefore has nothing to expand to, and would otherwise
      # recur until the stack ran out.
      sig { void }
      def reject_alias_cycles!
        @types.values.grep(Model::AliasDef).sort_by(&:name).each do |type|
          walk_aliases(type.target, [type.name])
        end
      end

      sig { returns(T::Array[String]) }
      def warnings = @warnings.to_a

      sig do
        params(namespace: String, type_mappings: T::Hash[String, RubyType],
               types: T::Hash[String, Model::TypeDef]).void
      end
      def initialize(namespace:, type_mappings: DEFAULT_TYPE_MAPPINGS, types: {})
        @namespace = namespace
        @type_mappings = type_mappings
        @types = types
        @warnings = T.let(Set.new, T::Set[String])
      end

      sig { params(schema: Model::Schema).returns(String) }
      def sorbet_type(schema)
        case schema
        when Model::Ref
          aliased = alias_target(schema)
          return sorbet_type(aliased) if aliased

          union?(schema) ? "#{@namespace}::Types::#{schema.name}::Value" : "#{@namespace}::Types::#{schema.name}"
        when Model::List then "T::Array[#{sorbet_type(schema.items)}]"
        when Model::Freeform
          values = schema.values
          "T::Hash[::String, #{values ? sorbet_type(values) : "T.untyped"}]"
        when Model::Untyped then "T.untyped"
        when Model::StringSchema, Model::IntegerSchema, Model::NumberSchema, Model::BooleanSchema
          ruby_type_for(schema).type
        else T.absurd(schema)
        end
      end

      sig { params(schema: Model::Schema, value: String).returns(String) }
      def from_wire_expr(schema, value:)
        case schema
        when Model::Ref
          aliased = alias_target(schema)
          aliased ? from_wire_expr(aliased, value: value) : "#{codec_for(schema)}.from_wire(#{value})"
        when Model::List
          "Oapi::Decode.each(#{value}) { |item| #{from_wire_expr(schema.items, value: "item")} }"
        when Model::Freeform
          values = schema.values
          return "Oapi::Decode.object(#{value})" if values.nil?

          "Oapi::Decode.values(#{value}) { |item| #{from_wire_expr(values, value: "item")} }"
        when Model::Untyped then value
        when Model::StringSchema, Model::IntegerSchema, Model::NumberSchema, Model::BooleanSchema
          "#{ruby_type_for(schema).codec}.from_wire(#{value})"
        else T.absurd(schema)
        end
      end

      NATIVE_LITERALS = T.let(
        {
          "::String" => [::String],
          "::Integer" => [::Integer],
          "::Float" => [::Float],
          "T::Boolean" => [::TrueClass, ::FalseClass]
        }.freeze,
        T::Hash[String, T::Array[T::Class[T.anything]]]
      )

      sig { params(schema: Model::Schema, value: T.untyped).returns(T::Boolean) }
      def literal_matches_type?(schema, value)
        NATIVE_LITERALS.fetch(sorbet_type(schema), []).any? { |native| value.is_a?(native) }
      end

      # Rails only hands back request_parameters verbatim for a JSON object; anything else it
      # wraps under "_json". The emitters need to know which shape a body will arrive in.
      sig { params(name: String).returns(String) }
      def codec_reference(name) = RubyType.codec_in("#{@namespace}::Types::#{name}")

      sig { params(schema: Model::Schema).returns(T::Boolean) }
      def object?(schema)
        case schema
        when Model::Ref then referent_object?(schema)
        when Model::Freeform, Model::Untyped then true
        when Model::List, Model::StringSchema, Model::IntegerSchema, Model::NumberSchema,
             Model::BooleanSchema
          false
        else T.absurd(schema)
        end
      end

      sig { params(schema: Model::Schema, value: String).returns(String) }
      def to_wire_expr(schema, value:)
        case schema
        when Model::Ref
          aliased = alias_target(schema)
          aliased ? to_wire_expr(aliased, value: value) : "#{codec_for(schema)}.to_wire(#{value})"
        when Model::List
          inner = to_wire_expr(schema.items, value: "item")
          inner == "item" ? value : "#{value}.map { |item| #{inner} }"
        when Model::Freeform
          values = schema.values
          return value if values.nil?

          inner = to_wire_expr(values, value: "item")
          inner == "item" ? value : "#{value}.transform_values { |item| #{inner} }"
        when Model::Untyped then value
        when Model::StringSchema, Model::IntegerSchema, Model::NumberSchema, Model::BooleanSchema
          "#{ruby_type_for(schema).codec}.to_wire(#{value})"
        else T.absurd(schema)
        end
      end

      private

      sig { params(schema: T.nilable(Model::Schema), seen: T::Array[String]).void }
      def walk_aliases(schema, seen)
        case schema
        when Model::Ref
          found = @types[schema.name]
          return unless found.is_a?(Model::AliasDef)

          if seen.include?(schema.name)
            raise SchemaError,
                  "#{schema.name} is defined in terms of itself, through " \
                  "#{seen.join(" -> ")} -> #{schema.name}. A schema that is only an alias for " \
                  "another cannot form a cycle: give one of them properties, or break the loop."
          end

          walk_aliases(found.target, seen + [schema.name])
        when Model::List then walk_aliases(schema.items, seen)
        when Model::Freeform then walk_aliases(schema.values, seen)
        end
      end

      sig { params(schema: Model::Ref).returns(String) }
      def codec_for(schema) = codec_reference(schema.name)

      sig { params(schema: Model::Ref).returns(T::Boolean) }
      def union?(schema) = @types[schema.name].is_a?(Model::UnionDef)

      sig { params(schema: Model::Ref).returns(T::Boolean) }
      def referent_object?(schema)
        found = @types[schema.name]
        return true if found.nil?

        case found
        when Model::ObjectDef then true
        when Model::EnumDef then false
        when Model::UnionDef then found.members.all? { |member| object?(member) }
        when Model::AliasDef then object?(found.target)
        else T.absurd(found)
        end
      end

      sig { params(schema: Model::Ref).returns(T.nilable(Model::Schema)) }
      def alias_target(schema)
        found = @types[schema.name]
        found.is_a?(Model::AliasDef) ? found.target : nil
      end

      sig { params(schema: Model::Schema).returns(RubyType) }
      def ruby_type_for(schema)
        override = Model::Schema.meta(schema).ruby_type
        return override if override

        type, format = scalar_kind(schema)
        requested = format ? "#{type}:#{format}" : type

        candidate_keys(type, format).each_with_index do |key, index|
          mapping = @type_mappings[key]
          next if mapping.nil?

          warn_about_unrecognised_format(requested, key) if index.positive?
          return mapping
        end

        raise SchemaError, unmapped_message(requested)
      end

      sig { params(type: String, format: T.nilable(String)).returns(T::Array[String]) }
      def candidate_keys(type, format) = format ? ["#{type}:#{format}", type] : [type]

      sig { params(schema: Model::Schema).returns([String, T.nilable(String)]) }
      def scalar_kind(schema)
        case schema
        when Model::StringSchema then ["string", schema.format]
        when Model::IntegerSchema then ["integer", schema.format]
        when Model::NumberSchema then ["number", schema.format]
        when Model::BooleanSchema then ["boolean", nil]
        else raise SchemaError, "#{schema.class} is not a scalar"
        end
      end

      sig { params(requested: String, used: String).void }
      def warn_about_unrecognised_format(requested, used)
        fallback = T.must(@type_mappings[used])
        message = <<~MESSAGE.strip
          #{requested.inspect} has no Ruby type mapped, so it is treated as #{used.inspect}
          (#{fallback.type}). If that is wrong, map it:

          #{mapping_snippet(requested)}
        MESSAGE
        @warnings << message
      end

      sig { params(key: String).returns(String) }
      def unmapped_message(key)
        "No Ruby type is mapped for #{key.inspect}. Add one to your config:\n\n#{mapping_snippet(key)}"
      end

      sig { params(key: String).returns(String) }
      def mapping_snippet(key)
        <<~SNIPPET.strip
          type_mappings:
            #{key.inspect}:
              type: "::YourType"
              codec: "YourApp::YourTypeCodec"   # extends or includes Oapi::Codec
        SNIPPET
      end
    end
  end
end
