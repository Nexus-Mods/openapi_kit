# frozen_string_literal: true

RSpec.describe OpenAPIKit::Body do
  describe OpenAPIKit::Body::Stream do
    def chunks(binary) = binary.enum_for(:each).to_a

    it "yields what the body writes into the sink" do
      binary = described_class.new(body: ->(sink) { sink.write("abc") && sink.write("def") })

      expect(chunks(binary)).to eq(%w[abc def])
    end

    it "accepts << as well as write" do
      binary = described_class.new(body: ->(sink) { sink << "abc" << "def" })

      expect(chunks(binary)).to eq(%w[abc def])
    end

    it "answers flush, which writes nothing of its own" do
      binary = described_class.new(body: ->(sink) { sink.flush.write("abc") })

      expect(chunks(binary)).to eq(%w[abc])
    end

    it "yields nothing for a body that writes nothing" do
      expect(chunks(described_class.new(body: ->(_sink) {}))).to be_empty
    end

    it "answers the byte count, so IO.copy_stream can drive the sink" do
      written = []
      binary = described_class.new(body: ->(sink) { written << sink.write("four") })

      chunks(binary)

      expect(written).to eq([4])
    end

    # IO.copy_stream reads into one buffer over and over, so the sink copies a chunk
    # before handing it on. Without that, every chunk here would hold the same bytes.
    it "copies each chunk out of the buffer IO.copy_stream reuses" do
      source = StringIO.new(("a" * 16_384) + ("b" * 16_384))
      binary = described_class.new(body: ->(sink) { IO.copy_stream(source, sink) })

      expect(chunks(binary).map { |bytes| bytes[0] }).to eq(%w[a b])
    end

    it "yields binary strings, whatever encoding the body wrote" do
      binary = described_class.new(body: ->(sink) { sink.write("é") })

      expect(chunks(binary).map(&:encoding)).to eq([Encoding::BINARY])
    end

    it "refuses a stream, which is not a body that writes one" do
      expect { described_class.new(body: StringIO.new("abc")) }.to raise_error(TypeError)
    end

    describe "what the block opened" do
      it "is closed by the block, not by openapi_kit" do
        file = Tempfile.new("body")
        file.write("stored")
        file.rewind

        chunks(described_class.new(body: ->(sink) { IO.copy_stream(file, sink) }))

        expect(file).not_to be_closed
      ensure
        file&.close
        file&.unlink
      end

      it "is closed the moment a client vanishes, by the block's own ensure" do
        Tempfile.create("body") do |source|
          source.write("abcdef")
          source.rewind
          opened = nil

          binary = described_class.new(
            body: lambda do |sink|
              File.open(source.path, "rb") do |io|
                opened = io
                io.each_char { |char| sink.write(char) }
              end
            end
          )

          seen = 0
          expect do
            binary.each { raise "client vanished" if (seen += 1) == 2 }
          end.to raise_error("client vanished")
          expect(opened).to be_closed
        end
      end
    end
  end

  describe OpenAPIKit::Body::File do
    it "answers the size of the file the server will send" do
      Tempfile.create("body") do |file|
        file.write("stored")
        file.flush

        expect(described_class.new(path: Pathname.new(file.path)).size).to eq(6)
      end
    end
  end

  it "distinguishes an absent body from one that is JSON null" do
    expect(OpenAPIKit::Body::Empty.new).not_to eq(OpenAPIKit::Body::Json.new(wire: nil))
  end
end
