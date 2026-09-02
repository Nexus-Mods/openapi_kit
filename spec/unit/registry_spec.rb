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
      expect(registry.sorbet_type(string("binary"))).to eq("::Oapi::UploadedFile")
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

  describe "#load_expr / #dump_expr" do
    it "calls the coder for a built-in scalar" do
      expect(registry.load_expr(string("date-time"), value: "v"))
        .to eq("Oapi::Coders::DateTime.load(v)")
      expect(registry.dump_expr(string("date-time"), value: "at"))
        .to eq("Oapi::Coders::DateTime.dump(at)")
    end

    it "calls the generated type's nested coder for a ref" do
      ref = Oapi::Ir::Ref.new(name: "Mod")
      expect(registry.load_expr(ref, value: "v"))
        .to eq("API::V3::Types::Mod::Coder.load(v)")
      expect(registry.dump_expr(ref, value: "mod")).to eq("API::V3::Types::Mod::Coder.dump(mod)")
    end

    it "maps over a list, and stays identity when the element needs no conversion" do
      list = Oapi::Ir::List.new(items: Oapi::Ir::Ref.new(name: "Mod"))
      expect(registry.load_expr(list, value: "v"))
        .to eq("Oapi::Decode.each(v) { |item| API::V3::Types::Mod::Coder.load(item) }")
      expect(registry.dump_expr(list, value: "mods"))
        .to eq("mods.map { |item| API::V3::Types::Mod::Coder.dump(item) }")
      expect(registry.dump_expr(Oapi::Ir::Untyped.new, value: "x")).to eq("x")
    end

    describe "custom types" do
      let(:mappings) do
        {
          "string:money" => Oapi::RubyType.new(type: "::Money", coder: "MyApp::MoneyCoder"),
          "string:legacy" => Oapi::RubyType.new(type: "::Legacy", coder: "MyApp::LegacyCoder")
        }
      end

      it "routes every custom type through its coder" do
        expect(registry.sorbet_type(string("money"))).to eq("::Money")
        expect(registry.load_expr(string("money"), value: "v")).to eq("MyApp::MoneyCoder.load(v)")
        expect(registry.dump_expr(string("money"), value: "price")).to eq("MyApp::MoneyCoder.dump(price)")
      end

      it "honours an x-ruby-type override on the schema itself" do
        schema = Oapi::Ir::StringSchema.new(
          meta: Oapi::Ir::Meta.new(
            ruby_type: Oapi::RubyType.new(type: "::Token", coder: "MyApp::TokenCoder")
          )
        )
        expect(registry.sorbet_type(schema)).to eq("::Token")
        expect(registry.load_expr(schema, value: "v")).to eq("MyApp::TokenCoder.load(v)")
      end
    end
  end

  # An unrecognised `format` is spec-compliant to ignore, so we use the base type --
  # but never silently: the warning names the config line that would change it.
  describe "unrecognised formats" do
    it "falls back to the base type" do
      expect(registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "unix-time"))).to eq("::Integer")
    end

    it "warns, naming the config that would change it" do
      registry.sorbet_type(Oapi::Ir::IntegerSchema.new(format: "unix-time"))

      expect(registry.warnings.join("\n"))
        .to match(/"integer:unix-time" has no Ruby type mapped, so it is treated as "integer"/)
      expect(registry.warnings.join("\n")).to match(/coder: "YourApp::YourTypeCoder"/)
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
