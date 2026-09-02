# frozen_string_literal: true

class Money
  attr_reader :cents

  def initialize(cents)
    @cents = cents
  end

  def ==(other) = other.is_a?(Money) && other.cents == cents
end

class MoneyCodecClass
  extend T::Sig
  extend T::Generic
  include Oapi::Codec::Contract

  Value = type_member { { fixed: Money } }

  sig { override.params(value: T.untyped).returns(Money) }
  def from_wire(value) = Money.new(Oapi::Codec::Integer::CODEC.from_wire(value))

  sig { override.params(value: Money).returns(Oapi::Wire) }
  def to_wire(value) = value.cents
end

MoneyCodec = MoneyCodecClass.new

class SaltedIdCodec
  extend T::Sig
  extend T::Generic
  include Oapi::Codec::Contract

  Value = type_member { { fixed: Integer } }

  sig { params(salt: String).void }
  def initialize(salt:)
    @salt = salt
  end

  sig { override.params(value: T.untyped).returns(Integer) }
  def from_wire(value) = Oapi::Codec::String::CODEC.from_wire(value).delete_prefix(@salt).to_i

  sig { override.params(value: Integer).returns(Oapi::Wire) }
  def to_wire(value) = "#{@salt}#{value}"
end

SALTED_ID_CODEC = SaltedIdCodec.new(salt: "nx_")

RSpec.describe Oapi::Codec::Contract do
  it "converts a type it does not own, with nothing mixed into that type" do
    expect(Money.ancestors.map(&:to_s).grep(/Oapi/)).to be_empty
    expect(MoneyCodec.from_wire("500")).to eq(Money.new(500))
    expect(MoneyCodec.to_wire(Money.new(500))).to eq(500)
  end

  it "is the one contract every codec implements, built-in or yours" do
    [Oapi::Codec::DateTime::CODEC, Oapi::Codec::Decimal::CODEC, MoneyCodec].each do |codec|
      expect(codec.class.ancestors).to include(described_class)
    end
  end

  describe "a codec that needs state" do
    it "carries its configuration on an instance" do
      expect(SALTED_ID_CODEC.from_wire("nx_42")).to eq(42)
      expect(SALTED_ID_CODEC.to_wire(42)).to eq("nx_42")
    end

    it "answers the same from_wire and to_wire calls a module codec does" do
      expect(SaltedIdCodec.ancestors).to include(described_class)
      expect(SALTED_ID_CODEC).to respond_to(:from_wire, :to_wire)
      expect(Oapi::Codec::Integer::CODEC).to respond_to(:from_wire, :to_wire)
    end

    it "can be configured differently more than once" do
      expect(SaltedIdCodec.new(salt: "a_").to_wire(1)).to eq("a_1")
      expect(SaltedIdCodec.new(salt: "b_").to_wire(1)).to eq("b_1")
    end

    it "does not shadow ::String and friends in the including class" do
      %w[String Integer Float Date DateTime].each do |name|
        expect(SaltedIdCodec.const_get(name)).to eq(Object.const_get(name))
      end
    end

    it "leaves Boolean unresolvable rather than pointing it at the codec" do
      expect { SaltedIdCodec.const_get("Boolean") }.to raise_error(NameError)
    end
  end
end
