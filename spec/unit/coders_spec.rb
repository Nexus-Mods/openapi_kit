# frozen_string_literal: true

class Money
  attr_reader :cents

  def initialize(cents)
    @cents = cents
  end

  def ==(other) = other.is_a?(Money) && other.cents == cents
end

RSpec.describe Oapi::Coders do
  describe "Integer" do
    it "accepts an integer and the string form a query parameter arrives as" do
      expect(described_class::Integer.load(42)).to eq(42)
      expect(described_class::Integer.load("42")).to eq(42)
      expect(described_class::Integer.load("-7")).to eq(-7)
    end

    it "refuses values that are not integers" do
      ["4.2", "x", "", 4.2, nil, []].each do |value|
        expect { described_class::Integer.load(value) }
          .to raise_error(Oapi::DecodeError, /expected an integer/)
      end
    end
  end

  describe "Boolean" do
    it "accepts booleans and their query-parameter spellings" do
      expect(described_class::Boolean.load(true)).to be(true)
      expect(described_class::Boolean.load("TRUE")).to be(true)
      expect(described_class::Boolean.load("1")).to be(true)
      expect(described_class::Boolean.load("false")).to be(false)
      expect(described_class::Boolean.load("0")).to be(false)
    end

    it "refuses anything else" do
      expect { described_class::Boolean.load("yes") }
        .to raise_error(Oapi::DecodeError, /expected a boolean/)
    end
  end

  describe "round trips" do
    it "normalises a date-time to UTC" do
      value = described_class::DateTime.load("2026-09-02T12:00:00+02:00")
      expect(described_class::DateTime.dump(value)).to eq("2026-09-02T10:00:00Z")
    end

    it "keeps decimal precision as a string" do
      expect(described_class::Decimal.dump(described_class::Decimal.load("1.50"))).to eq("1.5")
      expect(described_class::Decimal.load("0.1") + described_class::Decimal.load("0.2"))
        .to eq(described_class::Decimal.load("0.3"))
    end

    it "round trips base64 without the base64 gem" do
      expect(described_class::Byte.load("aGk=")).to eq("hi")
      expect(described_class::Byte.dump("hi")).to eq("aGk=")
    end

    it "round trips a date" do
      expect(described_class::Date.dump(described_class::Date.load("2026-09-02"))).to eq("2026-09-02")
    end
  end

  describe "Uuid" do
    it "accepts a well formed uuid" do
      expect(described_class::Uuid.load("0f3a2b1c-1111-2222-3333-444455556666"))
        .to eq("0f3a2b1c-1111-2222-3333-444455556666")
    end

    it "refuses a string that is not a uuid" do
      expect { described_class::Uuid.load("nope") }.to raise_error(Oapi::DecodeError, /expected a UUID/)
    end
  end
end

RSpec.describe Oapi::Decode do
  describe ".field" do
    it "decodes a present value" do
      expect(described_class.field({ "id" => "7" }, "id") { |v| Oapi::Coders::Integer.load(v) }).to eq(7)
    end

    it "attaches the pointer to a failure raised without one" do
      expect { described_class.field({ "id" => "x" }, "id") { |v| Oapi::Coders::Integer.load(v) } }
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
      expect(described_class.tristate({}, "bio") { |v| v }).to eq(Oapi::Absent::INSTANCE)
    end

    it "is Present(nil) for an explicit null" do
      expect(described_class.tristate({ "bio" => nil }, "bio") { |v| v })
        .to eq(Oapi::Present.new(value: nil))
    end

    it "is Present(value) for a value" do
      expect(described_class.tristate({ "bio" => "hi" }, "bio") { |v| Oapi::Coders::String.load(v) })
        .to eq(Oapi::Present.new(value: "hi"))
    end
  end

  describe ".each" do
    it "numbers the pointer by index" do
      expect { described_class.field({ "tags" => %w[1 x] }, "tags") { |v| described_class.each(v) { |i| Oapi::Coders::Integer.load(i) } } }
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

module MoneyCoder
  extend T::Sig
  extend Oapi::Coder

  sig { override.params(value: Oapi::Wire).returns(Money) }
  def self.load(value) = Money.new(Oapi::Coders::Integer.load(value))

  sig { override.params(value: Money).returns(Oapi::Wire) }
  def self.dump(value) = value.cents
end

RSpec.describe Oapi::Coder do
  it "converts a type it does not own, with nothing mixed into that type" do
    expect(Money.ancestors.map(&:to_s).grep(/Oapi/)).to be_empty
    expect(MoneyCoder.load("500")).to eq(Money.new(500))
    expect(MoneyCoder.dump(Money.new(500))).to eq(500)
  end

  it "is the one contract every coder implements, built-in or yours" do
    [Oapi::Coders::DateTime, Oapi::Coders::Decimal, MoneyCoder].each do |coder|
      expect(coder.singleton_class.ancestors).to include(described_class)
    end
  end
end
