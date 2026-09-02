# typed: strict
# frozen_string_literal: true

module Oapi
  module Types
    class Registry
      extend T::Sig

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
        when Ir::Ref then "#{codec_for(schema)}.load(#{value})"
        when Ir::List
          "Oapi::Decode.each(#{value}) { |item| #{load_expr(schema.items, value: "item")} }"
        when Ir::Freeform
          values = schema.values
          return "Oapi::Decode.object(#{value})" if values.nil?

          "Oapi::Decode.values(#{value}) { |item| #{load_expr(values, value: "item")} }"
        when Ir::Untyped then value
        when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
          "#{scalar(schema).codec}.load(#{value})"
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Schema, value: String).returns(String) }
      def dump_expr(schema, value:)
        case schema
        when Ir::Ref then "#{codec_for(schema)}.dump(#{value})"
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
          "#{scalar(schema).codec}.dump(#{value})"
        else T.absurd(schema)
        end
      end

      sig { params(schema: Ir::Ref).returns(String) }
      def codec_for(schema) = "#{@namespace}::Types::#{schema.name}::Codec"

      private

      sig { params(schema: Ir::Schema).returns(RubyType) }
      def scalar(schema)
        override = Ir::Schemas.meta(schema).ruby_type
        return override if override

        type, format = kind(schema)
        keys = format ? ["#{type}:#{format}", type] : [type]

        requested = T.must(keys.first)

        keys.each_with_index do |key, index|
          mapping = @type_mappings[key]
          return mapping if mapping

          raise SchemaError, unmapped_message(key) if Builtins.refusal(key)

          builtin = Builtins[key]
          next if builtin.nil?

          warn_unrecognised_format(requested, key) if index.positive?
          return builtin
        end

        raise SchemaError, unmapped_message(requested)
      end

      sig { params(requested: String, used: String).void }
      def warn_unrecognised_format(requested, used)
        message = <<~MESSAGE.strip
          #{requested.inspect} has no Ruby type mapped, so it is treated as #{used.inspect}
          (#{T.must(Builtins[used]).type}). If that is wrong, map it:

            type_mappings:
              #{requested.inspect}:
                type: "::YourType"
                codec: "YourApp::YourTypeCodec"   # extends or includes Oapi::Codec::Interface
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
        refusal = Builtins.refusal(key)
        preamble =
          if refusal
            "oapi does not guess a Ruby type for #{key.inspect}, because #{refusal}. Map it:"
          else
            "No Ruby type is mapped for #{key.inspect}. Add one to your config:"
          end

        <<~MESSAGE.strip
          #{preamble}

            type_mappings:
              #{key.inspect}:
                type: "::YourType"
                codec: "YourApp::YourTypeCodec"   # extends or includes Oapi::Codec::Interface
        MESSAGE
      end
    end
  end
end
