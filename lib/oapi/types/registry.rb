# typed: strict
# frozen_string_literal: true

module Oapi
  module Types
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

      sig { returns(T::Array[String]) }
      attr_reader :warnings

      sig { params(namespace: String, type_mappings: T::Hash[String, RubyType]).void }
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
          scalar(schema).type
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Schema, value: String).returns(String) }
      def load_expr(schema, value:)
        case schema
        when Ir::Ref then "#{coder_for(schema)}.load(#{value})"
        when Ir::List
          "Oapi::Decode.each(#{value}) { |item| #{load_expr(schema.items, value: "item")} }"
        when Ir::Freeform
          values = schema.values
          return "Oapi::Decode.object(#{value})" if values.nil?

          "Oapi::Decode.values(#{value}) { |item| #{load_expr(values, value: "item")} }"
        when Ir::Untyped then value
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
          "#{scalar(schema).coder}.load(#{value})"
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Schema, value: String).returns(String) }
      def dump_expr(schema, value:)
        case schema
        when Ir::Ref then "#{coder_for(schema)}.dump(#{value})"
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
          "#{scalar(schema).coder}.dump(#{value})"
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Ref).returns(String) }
      def coder_for(schema) = "#{@namespace}::Types::#{schema.name}::Coder"

      private

      sig { params(schema: Ir::Schema).returns(RubyType) }
      def scalar(schema)
        override = Ir::Schemas.meta(schema).ruby_type
        return override if override

        type, format = kind(schema)
        keys = format ? ["#{type}:#{format}", type] : [type]

        keys.each do |key|
          mapping = @type_mappings[key]
          return mapping if mapping
        end

        keys.each_with_index do |key, index|
          builtin = BUILTINS[key]
          next if builtin.nil?

          warn_unrecognised_format(T.must(keys.first), key) if index.positive?
          return RubyType.new(type: T.must(builtin[0]), coder: T.must(builtin[1]))
        end

        raise SchemaError, unmapped_message(T.must(keys.first))
      end

      sig { params(requested: String, used: String).void }
      def warn_unrecognised_format(requested, used)
        message = <<~MESSAGE.strip
          #{requested.inspect} has no Ruby type mapped, so it is treated as #{used.inspect}
          (#{T.must(T.must(BUILTINS[used])[0])}). If that is wrong, map it:

            type_mappings:
              #{requested.inspect}:
                type: "::YourType"
                coder: "YourApp::YourTypeCoder"   # a module extending Oapi::Coder
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
              #{key.inspect}:
                type: "::YourType"
                coder: "YourApp::YourTypeCoder"   # a module extending Oapi::Coder
        MESSAGE
      end
    end
  end
end
