# frozen_string_literal: true

require "tmpdir"

RSpec.describe Oapi::Writer do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  end

  subject(:writer) { described_class.new(output: @dir.join("out")) }

  it "marks every file it writes as generated" do
    path = writer.write("types.rb", "module Types; end")

    expect(path.read).to start_with("#{Oapi::MARKER}\n")
    expect(path.read).to end_with("module Types; end\n")
  end

  it "creates nested directories" do
    expect(writer.write("a/b/types.rb", "x").read).to include("x")
  end

  describe "#clean!" do
    it "removes files it previously generated" do
      stale = writer.write("stale.rb", "old")
      writer.clean!

      expect(stale).not_to exist
    end

    # The safety property: pointing `output` at a hand-written directory must not
    # destroy anything.
    it "refuses to delete a file it did not generate, and says why" do
      writer.write("generated.rb", "x")
      handwritten = @dir.join("out/precious.rb")
      handwritten.write("class Precious; end")

      expect { writer.clean! }
        .to raise_error(Oapi::Error, /Refusing to clean.*precious\.rb.*Point `output` at a directory oapi owns/m)
      expect(handwritten).to exist
    end

    it "is a no-op when the directory does not exist yet" do
      expect { writer.clean! }.not_to raise_error
    end
  end
end
