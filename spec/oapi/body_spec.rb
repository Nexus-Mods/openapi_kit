# frozen_string_literal: true

RSpec.describe Oapi::Body do
  describe Oapi::Body::Binary do
    def chunks(binary) = binary.enum_for(:each).to_a

    it "reads a stream in chunks of the size it was given" do
      binary = described_class.new(stream: StringIO.new("abcdefg"), chunk: 3)

      expect(chunks(binary)).to eq(%w[abc def g])
    end

    it "defaults to a chunk large enough for a small body to arrive whole" do
      binary = described_class.new(stream: StringIO.new("abcdefg"))

      expect(chunks(binary)).to eq(["abcdefg"])
    end

    it "yields nothing for an empty stream" do
      expect(chunks(described_class.new(stream: StringIO.new("")))).to be_empty
    end

    # read(0) answers "" rather than nil, so a non-positive chunk would never terminate.
    it "refuses a chunk size that would not make progress" do
      binary = described_class.new(stream: StringIO.new("abc"), chunk: 0)

      expect { chunks(binary) }.to raise_error(ArgumentError, /chunk must be positive/)
    end

    it "refuses a String, which is not a stream" do
      expect { described_class.new(stream: "abc") }.to raise_error(TypeError)
    end
  end

  it "distinguishes an absent body from one that is JSON null" do
    expect(Oapi::Body::Empty.new).not_to eq(Oapi::Body::Json.new(wire: nil))
  end
end
