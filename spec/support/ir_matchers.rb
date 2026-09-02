# frozen_string_literal: true

module IrValue
  module_function

  def of(value)
    case value
    when T::Struct
      value.class.props.keys
           .to_h { |key| [key, of(value.instance_variable_get("@#{key}"))] }
           .merge(__type__: value.class.name)
    when T::Enum then value.serialize
    when Array   then value.map { |item| of(item) }
    when Hash    then value.transform_values { |item| of(item) }
    else value
    end
  end
end

RSpec::Matchers.define :be_ir do |expected|
  match { |actual| IrValue.of(actual) == IrValue.of(expected) }

  failure_message do |actual|
    "expected IR to match\n  expected: #{IrValue.of(expected)}\n       got: #{IrValue.of(actual)}"
  end
end

RSpec::Matchers.define :contain_ir do |*expected|
  match do |actual|
    actual.map { |a| IrValue.of(a) }.sort_by(&:to_s) == expected.map { |e| IrValue.of(e) }.sort_by(&:to_s)
  end

  failure_message do |actual|
    "expected IR collection to match\n  expected: #{expected.map { |e| IrValue.of(e) }}\n       " \
      "got: #{actual.map { |a| IrValue.of(a) }}"
  end
end
