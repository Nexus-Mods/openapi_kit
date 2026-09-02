# frozen_string_literal: true

RSpec.describe Oapi::Codegen::Emit::Literal do
  describe ".string" do
    it "builds a plain literal" do
      expect(described_class.string("hello")).to eq(%("hello"))
    end

    it "escapes quotes in literal segments" do
      expect(described_class.string(%(say "hi"))).to eq(%("say \\"hi\\""))
    end

    it "escapes an interpolation that was meant literally" do
      expect(described_class.string("cost \#{x}")).to eq(%("cost \\\#{x}"))
    end

    it "leaves an expression segment as interpolation" do
      expect(described_class.string("got ", described_class.expr("value.inspect")))
        .to eq(%("got \#{value.inspect}"))
    end

    it "keeps quotes inside an expression segment" do
      expect(described_class.string("one of ", described_class.expr(%(VALUES.join(", ")))))
        .to eq(%("one of \#{VALUES.join(", ")}"))
    end

    it "produces Ruby that parses" do
      literal = described_class.string("one of ", described_class.expr(%(VALUES.join(", "))),
                                       %(, got "), described_class.expr("value"), %("))

      expect(Prism.parse("raise(#{literal})")).to be_success
    end
  end
end
