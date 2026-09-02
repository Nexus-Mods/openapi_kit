# frozen_string_literal: true

RSpec.describe Oapi::Codegen::TypeRegistry::Defaults do
  def mapping(key) = described_class[key]

  it "covers every base type" do
    expect(described_class::BASES.keys).to contain_exactly("string", "integer", "number", "boolean")
  end

  it "gives formats with a distinct Ruby type that type" do
    expect(mapping("string:date-time")).to be_ir(
      Oapi::Codegen::RubyType.new(type: "::Time", codec: "::Oapi::Codec::Primitive::DateTime::CODEC")
    )
    expect(mapping("string:decimal")).to be_ir(
      Oapi::Codegen::RubyType.new(type: "::BigDecimal", codec: "::Oapi::Codec::Primitive::Decimal::CODEC")
    )
  end

  it "resolves a format without its own type to the base entry itself" do
    expect(mapping("integer:int64")).to be_ir(described_class::BASES["integer"])
    expect(mapping("number:double")).to be_ir(described_class::BASES["number"])
    expect(mapping("string:hostname")).to be_ir(described_class::BASES["string"])
  end

  it "knows nothing about a format it does not recognise" do
    expect(mapping("integer:unix-time")).to be_nil
    expect(mapping("string:money")).to be_nil
  end

  it "maps binary content to the Rails upload type" do
    expect(mapping("string:binary")).to be_ir(
      Oapi::Codegen::RubyType.new(type: "::ActionDispatch::Http::UploadedFile",
                                  codec: "::Oapi::Rails::Codec::UploadedFile::CODEC")
    )
  end

  it "is overridden by merging, with no ordering rule" do
    mapped = Oapi::Codegen::RubyType.new(type: "::Tempfile", codec: "MyApp::UploadCodec")

    expect(described_class::TABLE.merge("string:binary" => mapped)["string:binary"]).to be(mapped)
  end

  it "names a codec implementing Oapi::Codec for every entry" do
    described_class::TABLE.each_value do |entry|
      codec = entry.codec.delete_prefix("::").split("::").reduce(Object) { |scope, name| scope.const_get(name) }

      expect(codec.class.ancestors).to include(Oapi::Codec), entry.codec
    end
  end
end
