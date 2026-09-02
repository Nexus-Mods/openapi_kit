# frozen_string_literal: true

RSpec.describe Oapi::Codec::Contract do
  # A type from a gem you do not control, with nothing of oapi's mixed into it.
  let(:money) do
    Class.new do
      attr_reader :cents

      def initialize(cents)
        @cents = cents
      end

      def ==(other) = other.class == self.class && other.cents == cents
    end
  end

  let(:money_codec) do
    Class.new do
      extend T::Sig
      extend T::Generic
      include Oapi::Codec::Contract

      Value = type_member { { fixed: T.untyped } }

      def from_wire(value) = Money.new(Oapi::Codec::Integer::CODEC.from_wire(value))
      def to_wire(value) = value.cents
    end.new
  end

  before { stub_const("Money", money) }

  it "converts a type it does not own" do
    expect(money.ancestors.map(&:to_s).grep(/Oapi/)).to be_empty
    expect(money_codec.from_wire("500")).to eq(Money.new(500))
    expect(money_codec.to_wire(Money.new(500))).to eq(500)
  end

  it "is the one contract every codec implements, built-in or yours" do
    [Oapi::Codec::DateTime::CODEC, Oapi::Codec::Decimal::CODEC, money_codec].each do |codec|
      expect(codec.class.ancestors).to include(described_class)
    end
  end

  # A module cannot satisfy the contract, since Value = type_member needs a class, so
  # every codec is an instance and can therefore carry configuration.
  describe "a codec that needs state" do
    let(:salted_id_codec) do
      Class.new do
        extend T::Sig
        extend T::Generic
        include Oapi::Codec::Contract

        Value = type_member { { fixed: T.untyped } }

        def initialize(salt:)
          @salt = salt
        end

        def from_wire(value) = Oapi::Codec::String::CODEC.from_wire(value).delete_prefix(@salt).to_i
        def to_wire(value) = "#{@salt}#{value}"
      end
    end

    it "carries its configuration on the instance" do
      codec = salted_id_codec.new(salt: "nx_")

      expect(codec.from_wire("nx_42")).to eq(42)
      expect(codec.to_wire(42)).to eq("nx_42")
    end

    it "can be configured differently more than once" do
      expect(salted_id_codec.new(salt: "a_").to_wire(1)).to eq("a_1")
      expect(salted_id_codec.new(salt: "b_").to_wire(1)).to eq("b_1")
    end

    # The contract must not shadow the core classes in the including class.
    it "does not shadow ::String and friends" do
      %w[String Integer Float Date DateTime].each do |name|
        expect(salted_id_codec.const_get(name)).to eq(Object.const_get(name))
      end
    end
  end
end
