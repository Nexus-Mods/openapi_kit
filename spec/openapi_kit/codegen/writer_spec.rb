# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenAPIKit::Codegen::Writer do
  subject(:writer) { described_class.new(output: @dir.join("out")) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  end

  it "marks every file it writes as generated" do
    path = writer.write("types.rb", "module Types; end")

    expect(path.read).to start_with("#{OpenAPIKit::Codegen::MARKER}\n")
    expect(path.read).to end_with("module Types; end\n")
  end

  it "creates nested directories" do
    expect(writer.write("a/b/types.rb", "x").read).to include("x")
  end

  # typify cannot emit unparseable Rust because quote! yields a TokenStream. Ruby has no
  # equivalent, so the writer parses instead: an escaping mistake in an emitter fails at
  # generation time rather than reaching a golden file.
  describe "syntax checking" do
    it "refuses to write Ruby that does not parse, and points at the line" do
      broken = <<~RUBY
        def from_wire(value)
          raise("expected one of "live", got")
        end
      RUBY

      expect { writer.write("types.rb", broken) }.to raise_error(
        OpenAPIKit::Error, /openapi_kit generated invalid Ruby in types\.rb at line 2.*This is a bug in openapi_kit/m
      )
    end

    it "writes nothing when the syntax check fails" do
      expect { writer.write("types.rb", "class Broken") }.to raise_error(OpenAPIKit::Error)
      expect(@dir.join("out/types.rb")).not_to exist
    end

    it "accepts valid Ruby" do
      expect { writer.write("types.rb", "class Fine; end") }.not_to raise_error
    end
  end

  describe "#write_all" do
    def source(path, contents) = OpenAPIKit::Codegen::Emit::SourceFile.new(path: path, contents: contents)

    it "refuses when two sources claim the same path, before deleting anything" do
      stale = writer.write("stale.rb", "old")

      expect { writer.write_all([source("a.rb", "class A; end"), source("a.rb", "class B; end")]) }
        .to raise_error(OpenAPIKit::Error, /generated more than one file for a\.rb.*name_overrides/m)
      expect(stale).to exist
    end

    # A Prism failure on the last file must not leave the previous output deleted.
    it "leaves existing output untouched when any file fails to parse" do
      stale = writer.write("stale.rb", "old")

      expect { writer.write_all([source("a.rb", "class A; end"), source("b.rb", "class Broken")]) }
        .to raise_error(OpenAPIKit::Error, /invalid Ruby in b\.rb/)
      expect(stale).to exist
      expect(@dir.join("out/a.rb")).not_to exist
    end
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
        .to raise_error(OpenAPIKit::Error,
                        /Refusing to clean.*precious\.rb.*Point `output` at a directory openapi_kit owns/m)
      expect(handwritten).to exist
    end

    it "is a no-op when the directory does not exist yet" do
      expect { writer.clean! }.not_to raise_error
    end
  end
end
