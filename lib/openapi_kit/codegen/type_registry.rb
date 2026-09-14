# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    class TypeRegistry
      extend T::Sig

      DEFAULT_TYPE_MAPPINGS = T.let(
        {
          "string" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "integer" => RubyType.new(type: "::Integer", codec: "::OpenAPIKit::Codec::Integer"),
          "number" => RubyType.new(type: "::Float", codec: "::OpenAPIKit::Codec::Float"),
          "boolean" => RubyType.new(type: "T::Boolean", codec: "::OpenAPIKit::Codec::Boolean"),

          "string:date-time" => RubyType.new(type: "::Time", codec: "::OpenAPIKit::Codec::DateTime"),
          "string:date" => RubyType.new(type: "::Date", codec: "::OpenAPIKit::Codec::Date"),
          "string:uuid" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::Uuid"),
          "string:byte" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::Byte"),
          "string:decimal" => RubyType.new(type: "::BigDecimal", codec: "::OpenAPIKit::Codec::Decimal"),

          "string:time" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:duration" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:email" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:idn-email" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:hostname" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:idn-hostname" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:ipv4" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:ipv6" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:uri" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:uri-reference" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:uri-template" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:iri" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:json-pointer" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:relative-json-pointer" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:regex" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),
          "string:password" => RubyType.new(type: "::String", codec: "::OpenAPIKit::Codec::String"),

          "integer:int32" => RubyType.new(type: "::Integer", codec: "::OpenAPIKit::Codec::Integer"),
          "integer:int64" => RubyType.new(type: "::Integer", codec: "::OpenAPIKit::Codec::Integer"),

          "number:float" => RubyType.new(type: "::Float", codec: "::OpenAPIKit::Codec::Float"),
          "number:double" => RubyType.new(type: "::Float", codec: "::OpenAPIKit::Codec::Float"),
          "number:decimal" => RubyType.new(type: "::BigDecimal", codec: "::OpenAPIKit::Codec::Decimal")
        }.freeze,
        T::Hash[String, RubyType]
      )

      sig { params(document: Model::Document, config: Config).returns(TypeRegistry) }
      def self.for(document, config)
        reject_binary_mapping!(config.type_mappings)

        registry = new(
          namespace: config.namespace,
          type_mappings: DEFAULT_TYPE_MAPPINGS.merge(config.type_mappings),
          types: document.types.to_h { |type| [Model::TypeDef.name_of(type), type] }
        )

        registry.reject_alias_cycles!
        registry
      end

      sig { params(mappings: T::Hash[String, RubyType]).void }
      def self.reject_binary_mapping!(mappings)
        return unless mappings.key?("string:binary")

        raise ConfigError,
              "type_mappings has an entry for \"string:binary\", but openapi_kit does not convert a " \
              "file with a codec: it has no wire form. An upload decodes to " \
              "::ActionDispatch::Http::UploadedFile and a binary response body is a stream, " \
              "neither through a codec. Convert to your own type in the handler, or use " \
              "format: byte to carry bytes inside a value."
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

      UPLOADED_FILE = "::ActionDispatch::Http::UploadedFile"

      BINARY = "::OpenAPIKit::Body::Binary"

      sig { params(schema: Model::Schema, value: String).returns(T.nilable(String)) }
      def from_form_expr(schema, value:)
        return nil unless schema.is_a?(Model::Ref) && @types[schema.name].is_a?(Model::FormDef)

        "#{@namespace}::Types::#{schema.name}::Form.from_parts(#{value})"
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
          "OpenAPIKit::Decode.each(#{value}) { |item| #{from_wire_expr(schema.items, value: "item")} }"
        when Model::Freeform
          values = schema.values
          return "OpenAPIKit::Decode.object(#{value})" if values.nil?

          "OpenAPIKit::Decode.values(#{value}) { |item| #{from_wire_expr(values, value: "item")} }"
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

      sig { params(name: String).returns(String) }
      def codec_reference(name) = "#{@namespace}::Types::#{name}::Codec"

      # Rails only hands back request_parameters verbatim for a JSON object, and wraps
      # anything else under "_json", so the emitters need to know which shape a body
      # will arrive in.
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

      sig { params(schema: Model::Schema).void }
      def reject_binary!(schema)
        return unless Model::Schema.file?(schema)

        raise SchemaError,
              "format: binary has no JSON type, so it cannot be converted by a codec. It is " \
              "only valid as a top-level property of a multipart/form-data request body, or " \
              "as the whole schema of a response body."
      end

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
        when Model::ObjectDef, Model::FormDef then true
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

        reject_binary!(schema)

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
              codec: "YourApp::YourTypeCodec"   # extends or includes OpenAPIKit::Codec
        SNIPPET
      end
    end
  end
end
