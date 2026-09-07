# frozen_string_literal: true

class SpecStatus < T::Enum
  enums do
    Live = new("live")
    Hidden = new("hidden")
  end
end

RSpec.describe Oapi::Decode do
  describe ".required" do
    it "decodes a present value" do
      expect(described_class.required({ "id" => "7" }, "id") do |v|
        Oapi::Codec::Integer.from_wire(v)
      end).to eq(7)
    end

    it "attaches the pointer to a failure raised without one" do
      expect { described_class.required({ "id" => "x" }, "id") { |v| Oapi::Codec::Integer.from_wire(v) } }
        .to raise_error(Oapi::DecodeError, "/id: expected an integer, got \"x\"")
    end

    it "reports a missing required key" do
      expect { described_class.required({}, "id") { |v| v } }
        .to raise_error(Oapi::DecodeError, "/id: is required")
    end

    # A key that is present and null is not missing, it is wrong, and the two are worth
    # telling apart even though neither can be returned.
    it "distinguishes an explicit null from a missing key" do
      expect { described_class.required({ "id" => nil }, "id") { |v| v } }
        .to raise_error(Oapi::DecodeError, "/id: must not be null")
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
  describe ".optional_nullable" do
    it "is Absent when the key is missing" do
      expect(described_class.optional_nullable({}, "bio") { |v| v }).to eq(Oapi::Absent.new)
    end

    it "is Present(nil) for an explicit null" do
      expect(described_class.optional_nullable({ "bio" => nil }, "bio") { |v| v })
        .to eq(Oapi::Present.new(value: nil))
    end

    it "hashes consistently with equality" do
      one = Oapi::Present.new(value: 1)
      other = Oapi::Present.new(value: 1)

      expect(other.hash).to eq(one.hash)
      expect(other).to eql(one)
      expect([one, other].uniq.size).to eq(1)
      expect({ Oapi::Absent.new => :x }[Oapi::Absent.new]).to eq(:x)
    end

    it "is Present(value) for a value" do
      expect(described_class.optional_nullable({ "bio" => "hi" }, "bio") do |v|
        Oapi::Codec::String.from_wire(v)
      end)
        .to eq(Oapi::Present.new(value: "hi"))
    end
  end

  describe ".each" do
    it "numbers the pointer by index" do
      expect { described_class.required({ "tags" => %w[1 x] }, "tags") { |v| described_class.each(v) { |i| Oapi::Codec::Integer.from_wire(i) } } }
        .to raise_error(Oapi::DecodeError, "/tags/1: expected an integer, got \"x\"")
    end
  end

  describe ".enum" do
    it "deserializes a member" do
      expect(described_class.enum(SpecStatus, "live")).to eq(SpecStatus::Live)
    end

    # The message lists what the document allows, which the enum already knows, so
    # nothing needs generating alongside it.
    it "names every permitted value when the wire value is not one" do
      expect { described_class.enum(SpecStatus, "banana") }
        .to raise_error(Oapi::DecodeError, %(expected one of live, hidden, got "banana"))
    end
  end

  describe ".object" do
    it "refuses a non-object" do
      expect { described_class.object([]) }
        .to raise_error(Oapi::DecodeError, /expected an object, got Array/)
    end
  end

  describe ".gather" do # lookup arrives as a typed block rather than the source object.
    it "collects the names that are present" do
      source = { "Application-Name" => "vortex", "Accept" => "application/json" }

      expect(described_class.gather(%w[Application-Name Accept]) { |name| source[name] })
        .to eq("Application-Name" => "vortex", "Accept" => "application/json")
    end

    it "omits a name the source does not have" do
      expect(described_class.gather(%w[Missing]) { |_name| nil }).to eq({})
    end

    it "returns a string keyed hash the other Decode helpers accept" do
      gathered = described_class.gather(%w[Page]) { |_name| "4" }

      expect(described_class.required(gathered, "Page") { |v| Oapi::Codec::Integer.from_wire(v) })
        .to eq(4)
    end
  end
end
