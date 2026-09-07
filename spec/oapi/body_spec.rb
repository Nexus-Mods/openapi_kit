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
    # It is refused on construction: by the time each runs, Rack has sent the headers.
    it "refuses a chunk size that would not make progress" do
      expect { described_class.new(stream: StringIO.new("abc"), chunk: 0) }
        .to raise_error(ArgumentError, /chunk must be positive/)
    end

    it "refuses a String, which is not a stream" do
      expect { described_class.new(stream: "abc") }.to raise_error(TypeError)
    end

    it "accepts a Tempfile, which is what an upload arrives as" do
      Tempfile.create("body") do |file|
        file.write("stored")
        file.rewind

        expect(chunks(described_class.new(stream: file))).to eq(["stored"])
      end
    end

    # Rack calls close on the body, but Rails' wrapper does not pass that on, so the
    # stream is closed when iteration ends or nothing closes it at all.
    it "closes the stream once it has been read" do
      stream = StringIO.new("abc")
      chunks(described_class.new(stream: stream))

      expect(stream).to be_closed
    end

    it "closes the stream when iteration is abandoned part way" do
      stream = StringIO.new("abcdef")

      expect { described_class.new(stream: stream, chunk: 2).each { raise "client vanished" } }
        .to raise_error("client vanished")
      expect(stream).to be_closed
    end
  end

  it "distinguishes an absent body from one that is JSON null" do
    expect(Oapi::Body::Empty.new).not_to eq(Oapi::Body::Json.new(wire: nil))
  end
end
