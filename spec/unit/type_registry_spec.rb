# frozen_string_literal: true

RSpec.describe Oapi::Codegen::TypeRegistry do
  subject(:registry) do
    described_class.new(namespace: "API::V3", type_mappings: Oapi::Codegen::TypeRegistry::Defaults::TABLE.merge(mappings))
  end

  let(:mappings) { {} }

  def string(format = nil) = Oapi::Codegen::Ir::StringSchema.new(format: format)

  describe "#sorbet_type" do
    it "maps the standard scalars and formats" do
      expect(registry.sorbet_type(string)).to eq("::String")
      expect(registry.sorbet_type(string("date-time"))).to eq("::Time")
      expect(registry.sorbet_type(string("date"))).to eq("::Date")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::IntegerSchema.new(format: "int64"))).to eq("::Integer")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::NumberSchema.new(format: "decimal"))).to eq("::BigDecimal")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::BooleanSchema.new)).to eq("T::Boolean")
    end

    it "falls back to the base type for a format with no special meaning" do
      expect(registry.sorbet_type(string("hostname"))).to eq("::String")
    end

    it "qualifies a ref into the configured namespace" do
      expect(registry.sorbet_type(Oapi::Codegen::Ir::Ref.new(name: "Mod"))).to eq("API::V3::Types::Mod")
    end

    it "nests collections" do
      list = Oapi::Codegen::Ir::List.new(items: Oapi::Codegen::Ir::Ref.new(name: "Mod"))
      expect(registry.sorbet_type(list)).to eq("T::Array[API::V3::Types::Mod]")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::List.new(items: list)))
        .to eq("T::Array[T::Array[API::V3::Types::Mod]]")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::Freeform.new(values: string)))
        .to eq("T::Hash[::String, ::String]")
      expect(registry.sorbet_type(Oapi::Codegen::Ir::Freeform.new)).to eq("T::Hash[::String, T.untyped]")
    end
  end

  describe "#from_wire_expr / #to_wire_expr" do
    it "calls the codec for a built-in scalar" do
      expect(registry.from_wire_expr(string("date-time"), value: "v"))
        .to eq("::Oapi::Codec::Primitive::DateTime::CODEC.from_wire(v)")
      expect(registry.to_wire_expr(string("date-time"), value: "at"))
        .to eq("::Oapi::Codec::Primitive::DateTime::CODEC.to_wire(at)")
    end

    it "calls the generated type's nested codec for a ref" do
      ref = Oapi::Codegen::Ir::Ref.new(name: "Mod")
      expect(registry.from_wire_expr(ref, value: "v"))
        .to eq("API::V3::Types::Mod::CODEC.from_wire(v)")
      expect(registry.to_wire_expr(ref, value: "mod")).to eq("API::V3::Types::Mod::CODEC.to_wire(mod)")
    end

    it "maps over a list, and stays identity when the element needs no conversion" do
      list = Oapi::Codegen::Ir::List.new(items: Oapi::Codegen::Ir::Ref.new(name: "Mod"))
      expect(registry.from_wire_expr(list, value: "v"))
        .to eq("Oapi::Decode.each(v) { |item| API::V3::Types::Mod::CODEC.from_wire(item) }")
      expect(registry.to_wire_expr(list, value: "mods"))
        .to eq("mods.map { |item| API::V3::Types::Mod::CODEC.to_wire(item) }")
      expect(registry.to_wire_expr(Oapi::Codegen::Ir::Untyped.new, value: "x")).to eq("x")
    end

    describe "custom types" do
      let(:mappings) do
        {
          "string:money" => Oapi::Codegen::RubyType.new(type: "::Money", codec: "MyApp::MoneyCodec"),
          "string:legacy" => Oapi::Codegen::RubyType.new(type: "::Legacy", codec: "MyApp::LegacyCodec")
        }
      end

      it "routes every custom type through its coder" do
        expect(registry.sorbet_type(string("money"))).to eq("::Money")
        expect(registry.from_wire_expr(string("money"), value: "v")).to eq("MyApp::MoneyCodec.from_wire(v)")
        expect(registry.to_wire_expr(string("money"), value: "price")).to eq("MyApp::MoneyCodec.to_wire(price)")
      end

      it "honours an x-ruby-type override on the schema itself" do
        schema = Oapi::Codegen::Ir::StringSchema.new(
          meta: Oapi::Codegen::Ir::Meta.new(
            ruby_type: Oapi::Codegen::RubyType.new(type: "::Token", codec: "MyApp::TokenCodec")
          )
        )
        expect(registry.sorbet_type(schema)).to eq("::Token")
        expect(registry.from_wire_expr(schema, value: "v")).to eq("MyApp::TokenCodec.from_wire(v)")
      end
    end
  end

  # An unrecognised `format` is spec-compliant to ignore, so we use the base type --
  # but never silently: the warning names the config line that would change it.
  describe "binary content" do
    it "resolves to the Rails upload type" do
      expect(registry.sorbet_type(string("binary"))).to eq("::ActionDispatch::Http::UploadedFile")
    end

    it "is overridden by mapping the format itself" do
      mapped = described_class.new(
        namespace: "API::V3",
        type_mappings: Oapi::Codegen::TypeRegistry::Defaults::TABLE.merge(
          "string:binary" => Oapi::Codegen::RubyType.new(type: "::Tempfile", codec: "MyApp::UploadCodec")
        )
      )

      expect(mapped.sorbet_type(string("binary"))).to eq("::Tempfile")
    end

    it "is not affected by mapping the base string type" do
      mapped = described_class.new(
        namespace: "API::V3",
        type_mappings: Oapi::Codegen::TypeRegistry::Defaults::TABLE.merge(
          "string" => Oapi::Codegen::RubyType.new(type: "::Text", codec: "MyApp::TextCodec")
        )
      )

      expect(mapped.sorbet_type(string("binary"))).to eq("::ActionDispatch::Http::UploadedFile")
    end
  end

  describe "unrecognised formats" do
    it "falls back to the base type" do
      expect(registry.sorbet_type(Oapi::Codegen::Ir::IntegerSchema.new(format: "unix-time"))).to eq("::Integer")
    end

    it "warns, naming the config that would change it" do
      registry.sorbet_type(Oapi::Codegen::Ir::IntegerSchema.new(format: "unix-time"))

      expect(registry.warnings.join("\n"))
        .to include('"integer:unix-time" has no Ruby type mapped, so it is treated as "integer"')
      expect(registry.warnings.join("\n")).to include('codec: "YourApp::YourTypeCodec"')
    end

    it "reports each unmapped format once, however many times it appears" do
      3.times { registry.sorbet_type(Oapi::Codegen::Ir::IntegerSchema.new(format: "unix-time")) }

      expect(registry.warnings.size).to eq(1)
    end

    it "does not warn for a format it maps deliberately" do
      registry.sorbet_type(string("date-time"))
      registry.sorbet_type(string("hostname"))

      expect(registry.warnings).to be_empty
    end
  end
end
