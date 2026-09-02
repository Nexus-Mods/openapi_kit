# typed: strict
# frozen_string_literal: true

module Oapi
  class ContainerError < Error
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_reader :problems

    sig { params(problems: T::Array[String]).void }
    def initialize(problems)
      @problems = problems
      listed = problems.map { |problem| "  - #{problem}" }.join("\n")
      super("The container does not satisfy the generated API:\n#{listed}")
    end
  end
end
