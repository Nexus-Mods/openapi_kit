# frozen_string_literal: true

require "open3"

RSpec.describe "codec type agreement" do
  def typecheck(*paths)
    Open3.capture2e("bundle", "exec", "srb", "tc", "./lib", "./sorbet/rbi", *paths).first
  end

  # Without the generic Value on Oapi::Codec, nothing tied from_wire's
  # return type to to_wire's parameter type: a codec could decode one type and
  # encode an unrelated one and still typecheck.
  it "rejects a codec whose from_wire and to_wire disagree" do
    output = typecheck("./spec/typecheck/mismatched_codec.rb")

    expect(output).to include(
      "Parameter `value` of type `String` not compatible with type of abstract method " \
      "`Oapi::Codec#to_wire`"
    )
  end

  it "accepts the built-in codecs, whose halves agree" do
    expect(typecheck).to include("No errors!")
  end
end
