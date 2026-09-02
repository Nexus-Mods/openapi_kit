# frozen_string_literal: true

RSpec.describe Oapi::Types::Registry do
  subject(:registry) { described_class.new(namespace: "API::V3", type_mappings: mappings) }

  let(:mappings) { {} }

  def string(format = nil) = Oapi::Ir::StringSchema.new(format: format)

  describe "#sorbet_type" do
    it "maps the standard scalars and formats" do
      expect(registry.sorbet_type(string)).to eq("::String")
      expect(registry.sorbet_type(string("date-time"))).to eq("::Time")
      expect(registry.sorbet_type(string("date"))).to eq("::Date")
      expect(registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "int64"))).to eq("::Integer")
      expect(registry.sorbet_type(Oapi::Ir::NumberSchema.new(format: "decimal"))).to eq("::BigDecimal")
      expect(registry.sorbet_type(Oapi::Ir::BooleanSchema.new)).to eq("T::Boolean")
    end

    it "falls back to the base type for a format with no special meaning" do
      expect(registry.sorbet_type(string("hostname"))).to eq("::String")
    end

    it "qualifies a ref into the configured namespace" do
      expect(registry.sorbet_type(Oapi::Ir::Ref.new(name: "Mod"))).to eq("API::V3::Types::Mod")
    end

    it "nests collections" do
      list = Oapi::Ir::List.new(items: Oapi::Ir::Ref.new(name: "Mod"))
      expect(registry.sorbet_type(list)).to eq("T::Array[API::V3::Types::Mod]")
      expect(registry.sorbet_type(Oapi::Ir::List.new(items: list)))
        .to eq("T::Array[T::Array[API::V3::Types::Mod]]")
      expect(registry.sorbet_type(Oapi::Ir::Freeform.new(values: string)))
        .to eq("T::Hash[::String, ::String]")
      expect(registry.sorbet_type(Oapi::Ir::Freeform.new)).to eq("T::Hash[::String, T.untyped]")
    end
  end

  describe "#from_wire_expr / #to_wire_expr" do
    it "calls the codec for a built-in scalar" do
      expect(registry.from_wire_expr(string("date-time"), value: "v"))
        .to eq("::Oapi::Codec::Scalar::DateTime.from_wire(v)")
      expect(registry.to_wire_expr(string("date-time"), value: "at"))
        .to eq("::Oapi::Codec::Scalar::DateTime.to_wire(at)")
    end

    it "calls the generated type's nested codec for a ref" do
      ref = Oapi::Ir::Ref.new(name: "Mod")
      expect(registry.from_wire_expr(ref, value: "v"))
        .to eq("API::V3::Codecs::Mod.from_wire(v)")
      expect(registry.to_wire_expr(ref, value: "mod")).to eq("API::V3::Codecs::Mod.to_wire(mod)")
    end

    it "maps over a list, and stays identity when the element needs no conversion" do
      list = Oapi::Ir::List.new(items: Oapi::Ir::Ref.new(name: "Mod"))
      expect(registry.from_wire_expr(list, value: "v"))
        .to eq("Oapi::Decode.each(v) { |item| API::V3::Codecs::Mod.from_wire(item) }")
      expect(registry.to_wire_expr(list, value: "mods"))
        .to eq("mods.map { |item| API::V3::Codecs::Mod.to_wire(item) }")
      expect(registry.to_wire_expr(Oapi::Ir::Untyped.new, value: "x")).to eq("x")
    end

    describe "custom types" do
      let(:mappings) do
        {
          "string:money" => Oapi::RubyType.new(type: "::Money", codec: "MyApp::MoneyCodec"),
          "string:legacy" => Oapi::RubyType.new(type: "::Legacy", codec: "MyApp::LegacyCodec")
        }
      end

      it "routes every custom type through its coder" do
        expect(registry.sorbet_type(string("money"))).to eq("::Money")
        expect(registry.from_wire_expr(string("money"), value: "v")).to eq("MyApp::MoneyCodec.from_wire(v)")
        expect(registry.to_wire_expr(string("money"), value: "price")).to eq("MyApp::MoneyCodec.to_wire(price)")
      end

      it "honours an x-ruby-type override on the schema itself" do
        schema = Oapi::Ir::StringSchema.new(
          meta: Oapi::Ir::Meta.new(
            ruby_type: Oapi::RubyType.new(type: "::Token", codec: "MyApp::TokenCodec")
          )
        )
        expect(registry.sorbet_type(schema)).to eq("::Token")
        expect(registry.from_wire_expr(schema, value: "v")).to eq("MyApp::TokenCodec.from_wire(v)")
      end
    end
  end

  # An unrecognised `format` is spec-compliant to ignore, so we use the base type --
  # but never silently: the warning names the config line that would change it.
  describe "formats it refuses to guess" do
    it "explains why binary has no built-in type, and how to map it" do
      expect { registry.sorbet_type(string("binary")) }
        .to raise_error(Oapi::SchemaError,
                        /does not guess a Ruby type for "string:binary".*depends on your framework/m)
    end

    it "still shows the config snippet" do
      expect { registry.sorbet_type(string("binary")) }
        .to raise_error(Oapi::SchemaError, /codec: "YourApp::YourTypeCodec"/)
    end

    it "is satisfied by mapping the format itself" do
      mapped = described_class.new(
        namespace: "API::V3",
        type_mappings: {
          "string:binary" => Oapi::RubyType.new(type: "::Tempfile", codec: "MyApp::UploadCodec")
        }
      )

      expect(mapped.sorbet_type(string("binary"))).to eq("::Tempfile")
    end

    it "is not satisfied by mapping the base type, which would swallow binary into a String" do
      mapped = described_class.new(
        namespace: "API::V3",
        type_mappings: { "string" => Oapi::RubyType.new(type: "::Text", codec: "MyApp::TextCodec") }
      )

      expect { mapped.sorbet_type(string("binary")) }
        .to raise_error(Oapi::SchemaError, /does not guess a Ruby type for "string:binary"/)
    end
  end

  describe "unrecognised formats" do
    it "falls back to the base type" do
      expect(registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "unix-time"))).to eq("::Integer")
    end

    it "warns, naming the config that would change it" do
      registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "unix-time"))

      expect(registry.warnings.join("\n"))
        .to include('"integer:unix-time" has no Ruby type mapped, so it is treated as "integer"')
      expect(registry.warnings.join("\n")).to include('codec: "YourApp::YourTypeCodec"')
    end

    it "reports each unmapped format once, however many times it appears" do
      3.times { registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "unix-time")) }

      expect(registry.warnings.size).to eq(1)
    end

    it "does not warn for a format it maps deliberately" do
      registry.sorbet_type(string("date-time"))
      registry.sorbet_type(string("hostname"))

      expect(registry.warnings).to be_empty
    end
  end
end
