# frozen_string_literal: true

RSpec.describe Oapi::Types::Builtins do
  it "covers every base type" do
    expect(described_class::BASES.keys).to contain_exactly("string", "integer", "number", "boolean")
  end

  it "gives formats with a distinct Ruby type that type" do
    expect(described_class["string:date-time"]).to be_ir(
      Oapi::RubyType.new(type: "::Time", codec: "::Oapi::Codec::DateTime")
    )
    expect(described_class["string:decimal"]).to be_ir(
      Oapi::RubyType.new(type: "::BigDecimal", codec: "::Oapi::Codec::Decimal")
    )
  end

  it "resolves a format without its own type to the base entry itself" do
    expect(described_class["integer:int64"]).to be_ir(described_class::BASES["integer"])
    expect(described_class["number:double"]).to be_ir(described_class::BASES["number"])
    expect(described_class["string:hostname"]).to be_ir(described_class::BASES["string"])
  end

  it "knows nothing about a format it does not recognise" do
    expect(described_class["integer:unix-time"]).to be_nil
    expect(described_class["string:money"]).to be_nil
  end

  it "refuses to guess a type for binary content rather than owning a wrapper" do
    expect(described_class["string:binary"]).to be_nil
    expect(described_class.refusal("string:binary")).to match(/depends on your framework/)
  end

  it "names a codec implementing Oapi::Codec for every entry" do
    described_class::TABLE.each_value do |ruby_type|
      expect(Object.const_get(ruby_type.codec).singleton_class.ancestors).to include(Oapi::Codec)
    end
  end
end
