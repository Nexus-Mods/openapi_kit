# frozen_string_literal: true

require "zeitwerk"

# Generated code is loaded by the host Rails application, so every file must define
# exactly the constant its path implies. Eager loading is what proves it: Zeitwerk
# raises Zeitwerk::NameError for any file whose constant does not match.
RSpec.describe "Zeitwerk compatibility" do
  it "eager loads the generated tree with no naming mismatch" do
    result = generate("server.yaml", modules: %w[Loaded])

    loader = Zeitwerk::Loader.new
    loader.push_dir(result[:dir].to_s)
    loader.setup

    expect { loader.eager_load }.not_to raise_error
  ensure
    loader&.unload
  end

  it "resolves every generated constant from its own path" do
    result = generate("server.yaml", modules: %w[Resolved])

    loader = Zeitwerk::Loader.new
    loader.push_dir(result[:dir].to_s)
    loader.setup
    loader.eager_load

    expect(Object.const_get("Resolved::Types::Mod")).to be < T::Struct
    expect(Object.const_get("Resolved::Types::Mod")::Codec).to be_a(Oapi::Codec::Contract)
    expect(Object.const_get("Resolved::Handlers::Mods")).to be_a(Module)
    expect(Object.const_get("Resolved::Operations::ListMods::Ok")).to be < T::Struct
    expect(Object.const_get("Resolved::Registry")).to be_a(Module)
  ensure
    loader&.unload
  end

  # An acronym namespace needs an inflection, which is how Rails handles acronym
  # constants generally: config.autoload_paths plus inflect, or the loader's own
  # inflector outside Rails.
  it "loads an acronym namespace when the inflector is told about it" do
    result = generate("server.yaml", modules: %w[API V1])

    loader = Zeitwerk::Loader.new
    loader.inflector.inflect("api" => "API")
    loader.push_dir(result[:dir].to_s)
    loader.setup
    loader.eager_load

    expect(Object.const_get("API::V1::Types::Mod")).to be < T::Struct
    expect(Object.const_get("API::V1::Handlers::Mods")).to be_a(Module)
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
