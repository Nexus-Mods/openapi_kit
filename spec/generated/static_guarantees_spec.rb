# frozen_string_literal: true

require "open3"

# These are properties of the generated code that only a typechecker can verify, so
# each one asserts on real `srb tc` output against a fixture built to violate it.
RSpec.describe "static guarantees" do
  def typecheck(*paths)
    Open3.capture2e("bundle", "exec", "srb", "tc", "./lib", "./sorbet/rbi", "./spec/golden", *paths).first
  end

  def invalid(name) = typecheck("./spec/typecheck/invalid/#{name}.rb")

  it "accepts the generated output and a complete handler" do
    expect(typecheck("./spec/typecheck/valid")).to include("No errors!")
  end

  it "rejects a handler that does not implement every operation of its tag" do
    expect(invalid("incomplete_handler")).to include(
      "Missing definition for abstract method `Server::Handlers::Mods#create_mod`"
    )
  end

  it "rejects a response case that does not handle every status" do
    expect(invalid("unhandled_response")).to include(
      "Control flow could reach `T.absurd` because the type " \
      "`Server::Operations::ListMods::BadRequest` wasn't handled"
    )
  end

  # `principal` names one type for the document, so an authenticator may narrow to a
  # variant of it but not step outside it.
  it "rejects an authenticator returning something that is not the configured principal" do
    expect(invalid("foreign_principal")).to include(
      "Return type `T.nilable(String)` does not match return type of abstract method " \
      "`Server::Security::BearerAuth#authenticate`"
    )
  end

  # Only for a codec that declares the contract's parameter type. Sorbet lets an override
  # widen it back to T.untyped, so this states the contract's intent; the loader's
  # refusals are what enforce it.
  it "rejects a codec that decodes a file, since Wire cannot carry one" do
    expect(invalid("file_codec")).to include("This code is unreachable")
  end

  it "rejects a render that does not handle every kind of body" do
    expect(invalid("unhandled_body")).to include(
      "Control flow could reach `T.absurd` because the type `Oapi::Body::Binary` wasn't handled"
    )
  end

  it "rejects a codec whose from_wire and to_wire disagree" do
    expect(invalid("mismatched_codec")).to include(
      "Parameter `value` of type `String` not compatible with type of abstract method " \
      "`Oapi::Codec::Contract#to_wire`"
    )
  end
end
