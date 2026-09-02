# frozen_string_literal: true

class Money
  attr_reader :cents

  def initialize(cents)
    @cents = cents
  end

  def ==(other) = other.is_a?(Money) && other.cents == cents
end

RSpec.describe Oapi::Codec do
  describe "Integer" do
    it "accepts an integer and the string form a query parameter arrives as" do
      expect(described_class::Integer.from_wire(42)).to eq(42)
      expect(described_class::Integer.from_wire("42")).to eq(42)
      expect(described_class::Integer.from_wire("-7")).to eq(-7)
    end

    it "refuses values that are not integers" do
      ["4.2", "x", "", 4.2, nil, []].each do |value|
        expect { described_class::Integer.from_wire(value) }
          .to raise_error(Oapi::DecodeError, /expected an integer/)
      end
    end
  end

  describe "Boolean" do
    it "accepts booleans and their query-parameter spellings" do
      expect(described_class::Boolean.from_wire(true)).to be(true)
      expect(described_class::Boolean.from_wire("TRUE")).to be(true)
      expect(described_class::Boolean.from_wire("1")).to be(true)
      expect(described_class::Boolean.from_wire("false")).to be(false)
      expect(described_class::Boolean.from_wire("0")).to be(false)
    end

    it "refuses anything else" do
      expect { described_class::Boolean.from_wire("yes") }
        .to raise_error(Oapi::DecodeError, /expected a boolean/)
    end
  end

  describe "round trips" do
    it "normalises a date-time to UTC" do
      value = described_class::DateTime.from_wire("2026-09-02T12:00:00+02:00")
      expect(described_class::DateTime.to_wire(value)).to eq("2026-09-02T10:00:00Z")
    end

    it "keeps decimal precision as a string" do
      expect(described_class::Decimal.to_wire(described_class::Decimal.from_wire("1.50"))).to eq("1.5")
      expect(described_class::Decimal.from_wire("0.1") + described_class::Decimal.from_wire("0.2"))
        .to eq(described_class::Decimal.from_wire("0.3"))
    end

    it "round trips base64 without the base64 gem" do
      expect(described_class::Byte.from_wire("aGk=")).to eq("hi")
      expect(described_class::Byte.to_wire("hi")).to eq("aGk=")
    end

    it "round trips a date" do
      expect(described_class::Date.to_wire(described_class::Date.from_wire("2026-09-02"))).to eq("2026-09-02")
    end
  end

  describe "Uuid" do
    it "accepts a well formed uuid" do
      expect(described_class::Uuid.from_wire("0f3a2b1c-1111-2222-3333-444455556666"))
        .to eq("0f3a2b1c-1111-2222-3333-444455556666")
    end

    it "refuses a string that is not a uuid" do
      expect { described_class::Uuid.from_wire("nope") }.to raise_error(Oapi::DecodeError, /expected a UUID/)
    end
  end
end

RSpec.describe Oapi::Decode do
  describe ".field" do
    it "decodes a present value" do
      expect(described_class.field({ "id" => "7" }, "id") { |v| Oapi::Codec::Integer.from_wire(v) }).to eq(7)
    end

    it "attaches the pointer to a failure raised without one" do
      expect { described_class.field({ "id" => "x" }, "id") { |v| Oapi::Codec::Integer.from_wire(v) } }
        .to raise_error(Oapi::DecodeError, "/id: expected an integer, got \"x\"")
    end

    it "reports a missing required key" do
      expect { described_class.field({}, "id") { |v| v } }
        .to raise_error(Oapi::DecodeError, "/id: is required")
    end
  end

  describe ".optional" do
    it "is nil for a missing key" do
      expect(described_class.optional({}, "name") { |v| v }).to be_nil
    end

    it "is nil for an explicit null" do
      expect(described_class.optional({ "name" => nil }, "name") { |v| v }).to be_nil
    end
  end

  # The only case where nil is genuinely ambiguous: optional AND nullable.
  describe ".tristate" do
    it "is Absent when the key is missing" do
      expect(described_class.tristate({}, "bio") { |v| v }).to eq(Oapi::Absent.new)
    end

    it "is Present(nil) for an explicit null" do
      expect(described_class.tristate({ "bio" => nil }, "bio") { |v| v })
        .to eq(Oapi::Present.new(value: nil))
    end

    it "is Present(value) for a value" do
      expect(described_class.tristate({ "bio" => "hi" }, "bio") { |v| Oapi::Codec::String.from_wire(v) })
        .to eq(Oapi::Present.new(value: "hi"))
    end
  end

  describe ".each" do
    it "numbers the pointer by index" do
      expect { described_class.field({ "tags" => %w[1 x] }, "tags") { |v| described_class.each(v) { |i| Oapi::Codec::Integer.from_wire(i) } } }
        .to raise_error(Oapi::DecodeError, "/tags/1: expected an integer, got \"x\"")
    end
  end

  describe ".object" do
    it "refuses a non-object" do
      expect { described_class.object([]) }
        .to raise_error(Oapi::DecodeError, /expected an object, got Array/)
    end
  end
end

module MoneyCodec
  extend T::Sig
  extend Oapi::Codec::Interface

  sig { override.params(value: Oapi::Wire).returns(Money) }
  def self.from_wire(value) = Money.new(Oapi::Codec::Integer.from_wire(value))

  sig { override.params(value: Money).returns(Oapi::Wire) }
  def self.to_wire(value) = value.cents
end

class SaltedIdCodec
  extend T::Sig
  include Oapi::Codec::Interface

  sig { params(salt: String).void }
  def initialize(salt:)
    @salt = salt
  end

  sig { override.params(value: Oapi::Wire).returns(Integer) }
  def from_wire(value) = Oapi::Codec::String.from_wire(value).delete_prefix(@salt).to_i

  sig { override.params(value: Integer).returns(Oapi::Wire) }
  def to_wire(value) = "#{@salt}#{value}"
end

SALTED_ID_CODEC = SaltedIdCodec.new(salt: "nx_")

RSpec.describe Oapi::Codec::Interface do
  it "converts a type it does not own, with nothing mixed into that type" do
    expect(Money.ancestors.map(&:to_s).grep(/Oapi/)).to be_empty
    expect(MoneyCodec.from_wire("500")).to eq(Money.new(500))
    expect(MoneyCodec.to_wire(Money.new(500))).to eq(500)
  end

  it "is the one contract every codec implements, built-in or yours" do
    [Oapi::Codec::DateTime, Oapi::Codec::Decimal, MoneyCodec].each do |codec|
      expect(codec.singleton_class.ancestors).to include(described_class)
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
      expect(Oapi::Codec::Integer).to respond_to(:from_wire, :to_wire)
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
