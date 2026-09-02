# frozen_string_literal: true

require "zeitwerk"

# Generated code is loaded by the host Rails application, so every file must define
# exactly the constant its path implies. Eager loading is what proves it: Zeitwerk
# raises Zeitwerk::NameError for any file whose constant does not match.
RSpec.describe "Zeitwerk compatibility" do
  it "eager loads the generated tree with no naming mismatch" do
    result = generate("server.yaml", modules: %w[Loaded], "container_prefix" => "v1")

    loader = Zeitwerk::Loader.new
    loader.push_dir(result[:dir].to_s)
    loader.setup

    expect { loader.eager_load }.not_to raise_error
  ensure
    loader&.unload
  end

  it "resolves every generated constant from its own path" do
    result = generate("server.yaml", modules: %w[Resolved], "container_prefix" => "v1")

    loader = Zeitwerk::Loader.new
    loader.push_dir(result[:dir].to_s)
    loader.setup
    loader.eager_load

    expect(Object.const_get("Resolved::Types::Mod")).to be < T::Struct
    expect(Object.const_get("Resolved::Codecs::Mod")).to be_a(Oapi::Codec)
    expect(Object.const_get("Resolved::Handlers::Mods")).to be_a(Module)
    expect(Object.const_get("Resolved::Operations::ListMods::Ok")).to be < T::Struct
    expect(Object.const_get("Resolved::Container")::HANDLERS.keys).to include("v1.handlers.mods")
  ensure
    loader&.unload
  end

  # Mutually recursive schemas were rejected because T::Struct evaluates a property
  # type when the class body runs. One constant per file makes Zeitwerk autoload the
  # other side on reference, so the cycle resolves.
  it "loads mutually recursive schemas that a single file could not express" do
    result = generate("cyclic.yaml", modules: %w[Cyclic])

    loader = Zeitwerk::Loader.new
    loader.push_dir(result[:dir].to_s)
    loader.setup
    loader.eager_load

    author = Object.const_get("Cyclic::Types::Author")
    book = Object.const_get("Cyclic::Types::Book")

    expect(author.new(books: [book.new(author: nil)]).books.first.author).to be_nil
  ensure
    loader&.unload
  end
end
