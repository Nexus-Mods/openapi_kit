# typed: strict
# frozen_string_literal: true

module Oapi
  module Naming
    extend T::Sig

    RESERVED = T.let(
      %w[
        BEGIN END alias and begin break case class def defined? do else elsif end ensure
        false for if in module next nil not or redo rescue retry return self super then
        true undef unless until when while yield __FILE__ __LINE__ __ENCODING__
      ].freeze,
      T::Array[String]
    )

    sig { params(string: String).returns(T::Array[String]) }
    def self.words(string)
      string
        .to_s
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2') # HTTPSConnection -> HTTPS Connection
        .gsub(/([a-z\d])([A-Z])/, '\1 \2')     # gameDomain      -> game Domain
        .split(/[^a-zA-Z0-9]+/)
        .reject(&:empty?)
    end

    sig { params(string: String).returns(String) }
    def self.snake(string) = words(string).map(&:downcase).join("_")

    sig { params(string: String).returns(String) }
    def self.pascal(string) = words(string).map(&:capitalize).join

    sig { params(string: String).returns(String) }
    def self.camel(string)
      pascal(string).then { |name| name.empty? ? name : "#{name[0].to_s.downcase}#{name[1..]}" }
    end

    SHADOWED = T.let(
      (Object.instance_methods + Kernel.instance_methods).to_set(&:to_s).freeze,
      T::Set[String]
    )

    sig { params(string: String).returns(Symbol) }
    def self.identifier(string)
      name = snake(string)
      name = "value" if name.empty?
      name = "n#{name}" if name.match?(/\A\d/)
      name = "#{name}_" if RESERVED.include?(name) || SHADOWED.include?(name)
      name.to_sym
    end

    sig { params(string: String).returns(String) }
    def self.constant(string)
      name = pascal(string)
      name = "Value" if name.empty?
      name = "Value#{name}" if name.match?(/\A\d/)
      name
    end

    sig { params(value: T.untyped).returns(String) }
    def self.enum_member(value)
      case value
      when ::String  then constant(value)
      when ::Integer then "Value#{value.negative? ? "Minus#{value.abs}" : value}"
      when true      then "True"
      when false     then "False"
      else constant(value.to_s)
      end
    end

    sig { params(string: String).returns(String) }
    def self.file_name(string) = "#{snake(string)}.rb"
  end
end
