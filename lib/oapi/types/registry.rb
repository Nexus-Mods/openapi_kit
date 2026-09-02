# typed: strict
# frozen_string_literal: true

module Oapi
  module Types
    module ScalarBinding
      extend T::Helpers
      sealed!
    end

    class CoderBinding < T::Struct
      include ScalarBinding
      const :type, String
      const :coder, String
    end

    class CodableBinding < T::Struct
      include ScalarBinding
      const :type, String
    end

    class Registry
      extend T::Sig

      BUILTINS = T.let(
        {
          "string" => ["::String", "Oapi::Coders::String"],
          "string:date-time" => ["::Time", "Oapi::Coders::DateTime"],
          "string:date" => ["::Date", "Oapi::Coders::Date"],
          "string:uuid" => ["::String", "Oapi::Coders::Uuid"],
          "string:byte" => ["::String", "Oapi::Coders::Byte"],
          "string:binary" => ["::Oapi::UploadedFile", "Oapi::Coders::Binary"],
          "string:decimal" => ["::BigDecimal", "Oapi::Coders::Decimal"],
          "string:time" => ["::String", "Oapi::Coders::String"],
          "string:duration" => ["::String", "Oapi::Coders::String"],
          "string:email" => ["::String", "Oapi::Coders::String"],
          "string:idn-email" => ["::String", "Oapi::Coders::String"],
          "string:hostname" => ["::String", "Oapi::Coders::String"],
          "string:idn-hostname" => ["::String", "Oapi::Coders::String"],
          "string:ipv4" => ["::String", "Oapi::Coders::String"],
          "string:ipv6" => ["::String", "Oapi::Coders::String"],
          "string:uri" => ["::String", "Oapi::Coders::String"],
          "string:uri-reference" => ["::String", "Oapi::Coders::String"],
          "string:uri-template" => ["::String", "Oapi::Coders::String"],
          "string:iri" => ["::String", "Oapi::Coders::String"],
          "string:json-pointer" => ["::String", "Oapi::Coders::String"],
          "string:regex" => ["::String", "Oapi::Coders::String"],
          "string:password" => ["::String", "Oapi::Coders::String"],
          "integer" => ["::Integer", "Oapi::Coders::Integer"],
          "integer:int32" => ["::Integer", "Oapi::Coders::Integer"],
          "integer:int64" => ["::Integer", "Oapi::Coders::Integer"],
          "number" => ["::Float", "Oapi::Coders::Float"],
          "number:float" => ["::Float", "Oapi::Coders::Float"],
          "number:double" => ["::Float", "Oapi::Coders::Float"],
          "number:decimal" => ["::BigDecimal", "Oapi::Coders::Decimal"],
          "boolean" => ["T::Boolean", "Oapi::Coders::Boolean"]
        }.freeze,
        T::Hash[String, [String, String]]
      )

      sig { params(binding: ScalarBinding).returns(String) }
      def self.binding_type(binding)
        case binding
        when CoderBinding, CodableBinding then binding.type
        else T.absurd(binding)
        end
      end

      sig { returns(T::Array[String]) }
      attr_reader :warnings

      sig { params(namespace: String, type_mappings: T::Hash[String, TypeMapping]).void }
      def initialize(namespace:, type_mappings: {})
        @namespace = namespace
        @type_mappings = type_mappings
        @warnings = T.let([], T::Array[String])
      end

      sig { params(schema: Ir::Schema).returns(String) }
      def sorbet_type(schema)
        case schema
        when Ir::Ref then "#{@namespace}::Types::#{schema.name}"
        when Ir::List then "T::Array[#{sorbet_type(schema.items)}]"
        when Ir::Freeform
          values = schema.values
          "T::Hash[::String, #{values ? sorbet_type(values) : "T.untyped"}]"
        when Ir::Untyped then "T.untyped"
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
          Registry.binding_type(scalar(schema))
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Schema, value: String, pointer: String).returns(String) }
      def load_expr(schema, value:, pointer:)
        case schema
        when Ir::Ref then "#{@namespace}::Types::#{schema.name}.from_openapi(#{value}, #{pointer})"
        when Ir::List
          inner = load_expr(schema.items, value: "item", pointer: "item_pointer")
          "Oapi::Decode.each(#{value}, #{pointer}) { |item, item_pointer| #{inner} }"
        when Ir::Freeform
          values = schema.values
          return "Oapi::Decode.object(#{value}, #{pointer})" if values.nil?

          inner = load_expr(values, value: "item", pointer: "#{pointer_join(pointer)}key")
          "Oapi::Decode.object(#{value}, #{pointer}).to_h { |key, item| [key, #{inner}] }"
        when Ir::Untyped then value
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
          binding = scalar(schema)
          case binding
          when CoderBinding then "#{binding.coder}.load(#{value})"
          when CodableBinding then "#{binding.type}.from_openapi(#{value})"
          else T.absurd(binding)
          end
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Schema, value: String).returns(String) }
      def dump_expr(schema, value:)
        case schema
        when Ir::Ref then "#{value}.to_openapi"
        when Ir::List
          inner = dump_expr(schema.items, value: "item")
          inner == "item" ? value : "#{value}.map { |item| #{inner} }"
        when Ir::Freeform
          values = schema.values
          return value if values.nil?

          inner = dump_expr(values, value: "item")
          inner == "item" ? value : "#{value}.transform_values { |item| #{inner} }"
        when Ir::Untyped then value
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
          binding = scalar(schema)
          case binding
          when CoderBinding then "#{binding.coder}.dump(#{value})"
          when CodableBinding then "#{value}.to_openapi"
          else T.absurd(binding)
          end
        else T.absurd(schema)
        end
      end

      private

      sig { params(pointer: String).returns(String) }
      def pointer_join(pointer)
        pointer.start_with?('"') && pointer.end_with?('"') ? "#{pointer[0..-2]}/" : "#{pointer} + \"/\" + "
      end

      sig { params(schema: Ir::Schema).returns(ScalarBinding) }
      def scalar(schema)
        override = Ir::Schemas.meta(schema).ruby_type
        return CodableBinding.new(type: override) if override

        type, format = kind(schema)
        keys = format ? ["#{type}:#{format}", type] : [type]

        keys.each do |key|
          mapping = @type_mappings[key]
          next if mapping.nil?

          coder = mapping.coder
          return coder ? CoderBinding.new(type: mapping.type, coder: coder) : CodableBinding.new(type: mapping.type)
        end

        keys.each_with_index do |key, index|
          builtin = BUILTINS[key]
          next if builtin.nil?

          warn_unrecognised_format(T.must(keys.first), key) if index.positive?
          return CoderBinding.new(type: T.must(builtin[0]), coder: T.must(builtin[1]))
        end

        raise SchemaError, unmapped_message(T.must(keys.first))
      end

      sig { params(requested: String, used: String).void }
      def warn_unrecognised_format(requested, used)
        message = <<~MESSAGE.strip
          #{requested.inspect} has no Ruby type mapped, so it is treated as #{used.inspect}
          (#{Registry.binding_type(CoderBinding.new(type: T.must(T.must(BUILTINS[used])[0]),
                                                    coder: T.must(T.must(BUILTINS[used])[1])))}).
          If that is wrong, map it:

            type_mappings:
              #{requested.inspect}: "::YourType"          # a class including Oapi::Codable

          or, for a type you do not own:

            type_mappings:
              #{requested.inspect}:
                type: "::YourType"
                coder: "YourApp::YourTypeCoder"     # a module extending Oapi::Coder
        MESSAGE
        @warnings << message unless @warnings.include?(message)
      end

      sig { params(schema: Ir::Schema).returns([String, T.nilable(String)]) }
      def kind(schema)
        case schema
        when Ir::StringSchema then ["string", schema.format]
        when Ir::IntegerSchema then ["integer", schema.format]
        when Ir::NumberSchema then ["number", schema.format]
        when Ir::BooleanSchema then ["boolean", nil]
        else raise SchemaError, "#{schema.class} is not a scalar"
        end
      end

      sig { params(key: String).returns(String) }
      def unmapped_message(key)
        <<~MESSAGE.strip
          No Ruby type is mapped for #{key.inspect}. Add one to your config:

            type_mappings:
              #{key.inspect}: "::YourType"          # a class including Oapi::Codable

          or, for a type you do not own:

            type_mappings:
              #{key.inspect}:
                type: "::YourType"
                coder: "YourApp::YourTypeCoder"     # a module extending Oapi::Coder
        MESSAGE
      end
    end
  end
end
