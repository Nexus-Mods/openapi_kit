# frozen_string_literal: true

class ForeignMoney
  attr_reader :cents

  def initialize(cents)
    @cents = cents
  end

  def ==(other) = other.is_a?(self.class) && other.cents == cents
end

module ForeignMoneyCoder
  extend T::Sig
  extend Oapi::Coder

  sig { override.params(value: Oapi::Wire).returns(ForeignMoney) }
  def self.load(value) = ForeignMoney.new(Oapi::Coders::Integer.load(value))

  sig { override.params(value: ForeignMoney).returns(Oapi::Wire) }
  def self.dump(value) = value.cents
end

RSpec.describe Oapi::Coder do
  it "coerces a type you do not own without monkeypatching it" do
    expect(ForeignMoney.ancestors).not_to include(Oapi::Codable)
    expect(ForeignMoneyCoder.load("500")).to eq(ForeignMoney.new(500))
    expect(ForeignMoneyCoder.dump(ForeignMoney.new(500))).to eq(500)
  end

  it "is the same contract the built-in coders implement" do
    expect(Oapi::Coders::DateTime.singleton_class.ancestors).to include(described_class)
    expect(Oapi::Coders::Decimal.singleton_class.ancestors).to include(described_class)
  end
end
