# typed: strict
# frozen_string_literal: true

module Oapi
  class TypeRegistry
    extend T::Sig

    sig { params(document: Ir::Document, config: Config).returns(TypeRegistry) }
    def self.for(document, config)
      new(
        namespace: config.namespace,
        type_mappings: Defaults::TABLE.merge(config.type_mappings),
        types: document.types.to_h { |type| [Ir::TypeDef.name_of(type), type] }
      )
    end

    sig { returns(T::Array[String]) }
    attr_reader :warnings

    sig do
      params(namespace: String, type_mappings: T::Hash[String, RubyType],
             types: T::Hash[String, Ir::TypeDef]).void
    end
    def initialize(namespace:, type_mappings: Defaults::TABLE, types: {})
      @namespace = namespace
      @type_mappings = type_mappings
      @types = types
      @warnings = T.let([], T::Array[String])
    end

    sig { params(schema: Ir::Schema).returns(String) }
    def sorbet_type(schema)
      case schema
      when Ir::Ref
        aliased = alias_target(schema)
        aliased ? sorbet_type(aliased) : "#{@namespace}::Types::#{schema.name}"
      when Ir::List then "T::Array[#{sorbet_type(schema.items)}]"
      when Ir::Freeform
        values = schema.values
        "T::Hash[::String, #{values ? sorbet_type(values) : "T.untyped"}]"
      when Ir::Untyped then "T.untyped"
      when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
        ruby_type_for(schema).type
      else T.absurd(schema)
      end
    end

    sig { params(schema: Ir::Schema, value: String).returns(String) }
    def from_wire_expr(schema, value:)
      case schema
      when Ir::Ref
        aliased = alias_target(schema)
        aliased ? from_wire_expr(aliased, value: value) : "#{codec_for(schema)}.from_wire(#{value})"
      when Ir::List
        "Oapi::Decode.each(#{value}) { |item| #{from_wire_expr(schema.items, value: "item")} }"
      when Ir::Freeform
        values = schema.values
        return "Oapi::Decode.object(#{value})" if values.nil?

        "Oapi::Decode.values(#{value}) { |item| #{from_wire_expr(values, value: "item")} }"
      when Ir::Untyped then value
      when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
        "#{ruby_type_for(schema).codec}.from_wire(#{value})"
      else T.absurd(schema)
      end
    end

    sig { params(schema: Ir::Schema, value: String).returns(String) }
    def to_wire_expr(schema, value:)
      case schema
      when Ir::Ref
        aliased = alias_target(schema)
        aliased ? to_wire_expr(aliased, value: value) : "#{codec_for(schema)}.to_wire(#{value})"
      when Ir::List
        inner = to_wire_expr(schema.items, value: "item")
        inner == "item" ? value : "#{value}.map { |item| #{inner} }"
      when Ir::Freeform
        values = schema.values
        return value if values.nil?

        inner = to_wire_expr(values, value: "item")
        inner == "item" ? value : "#{value}.transform_values { |item| #{inner} }"
      when Ir::Untyped then value
      when Ir::StringSchema, Ir::IntegerSchema, Ir::NumberSchema, Ir::BooleanSchema
        "#{ruby_type_for(schema).codec}.to_wire(#{value})"
      else T.absurd(schema)
      end
    end

    private

    sig { params(schema: Ir::Ref).returns(String) }
    def codec_for(schema) = "#{@namespace}::Codecs::#{schema.name}"

    sig { params(schema: Ir::Ref).returns(T.nilable(Ir::Schema)) }
    def alias_target(schema)
      found = @types[schema.name]
      found.is_a?(Ir::AliasDef) ? found.target : nil
    end

    sig { params(schema: Ir::Schema).returns(RubyType) }
    def ruby_type_for(schema)
      override = Ir::Schema.meta(schema).ruby_type
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

    sig { params(schema: Ir::Schema).returns([String, T.nilable(String)]) }
    def scalar_kind(schema)
      case schema
      when Ir::StringSchema then ["string", schema.format]
      when Ir::IntegerSchema then ["integer", schema.format]
      when Ir::NumberSchema then ["number", schema.format]
      when Ir::BooleanSchema then ["boolean", nil]
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
      @warnings << message unless @warnings.include?(message)
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
