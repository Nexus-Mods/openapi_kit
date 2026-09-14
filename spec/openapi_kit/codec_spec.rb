# frozen_string_literal: true

RSpec.describe OpenAPIKit::Codec do
  describe "Integer" do
    it "accepts an integer and the string form a query parameter arrives as" do
      expect(described_class::Integer.from_wire(42)).to eq(42)
      expect(described_class::Integer.from_wire("42")).to eq(42)
      expect(described_class::Integer.from_wire("-7")).to eq(-7)
    end

    it "refuses values that are not integers" do
      ["4.2", "x", "", 4.2, nil, []].each do |value|
        expect { described_class::Integer.from_wire(value) }
          .to raise_error(OpenAPIKit::DecodeError, /expected an integer/)
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
        .to raise_error(OpenAPIKit::DecodeError, /expected a boolean/)
    end
  end

  describe "round trips" do
    it "normalises a date-time to UTC" do
      value = described_class::DateTime.from_wire("2026-09-02T12:00:00+02:00")
      expect(described_class::DateTime.to_wire(value)).to eq("2026-09-02T10:00:00.000Z")
    end

    it "keeps the sub-second precision Rails renders, so a migrating client sees no change" do
      value = described_class::DateTime.from_wire("2026-09-02T12:00:00.250Z")

      expect(described_class::DateTime.to_wire(value)).to eq("2026-09-02T12:00:00.250Z")
    end

    it "keeps decimal precision as a string" do
      decimal = described_class::Decimal

      expect(decimal.to_wire(decimal.from_wire("1.50"))).to eq("1.5")
      expect(decimal.from_wire("0.1") + decimal.from_wire("0.2")).to eq(decimal.from_wire("0.3"))
    end

    it "round trips base64 without the base64 gem" do
      expect(described_class::Byte.from_wire("aGk=")).to eq("hi")
      expect(described_class::Byte.to_wire("hi")).to eq("aGk=")
    end

    it "round trips a date" do
      date = described_class::Date

      expect(date.to_wire(date.from_wire("2026-09-02"))).to eq("2026-09-02")
    end
  end

  describe "Uuid" do
    it "accepts a well formed uuid" do
      expect(described_class::Uuid.from_wire("0f3a2b1c-1111-2222-3333-444455556666"))
        .to eq("0f3a2b1c-1111-2222-3333-444455556666")
    end

    it "refuses a string that is not a uuid" do
      expect { described_class::Uuid.from_wire("nope") }.to raise_error(OpenAPIKit::DecodeError, /expected a UUID/)
    end
  end
end
