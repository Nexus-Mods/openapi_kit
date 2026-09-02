# frozen_string_literal: true

RSpec.describe Oapi::Decode do
  describe ".field" do
    it "decodes a present value" do
      expect(described_class.field({ "id" => "7" }, "id") do |v|
        Oapi::Codec::Integer.from_wire(v)
      end).to eq(7)
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

    it "hashes consistently with equality" do
      one = Oapi::Present.new(value: 1)
      other = Oapi::Present.new(value: 1)

      expect(other.hash).to eq(one.hash)
      expect(other).to eql(one)
      expect([one, other].uniq.size).to eq(1)
      expect({ Oapi::Absent.new => :x }[Oapi::Absent.new]).to eq(:x)
    end

    it "is Present(value) for a value" do
      expect(described_class.tristate({ "bio" => "hi" }, "bio") do |v|
        Oapi::Codec::String.from_wire(v)
      end)
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

      expect(described_class.field(gathered, "Page") { |v| Oapi::Codec::Integer.from_wire(v) })
        .to eq(4)
    end
  end
end
