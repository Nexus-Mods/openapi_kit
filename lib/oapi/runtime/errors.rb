# typed: strict
# frozen_string_literal: true

module Oapi
  class DecodeError < StandardError
    extend T::Sig

    sig { returns(String) }
    attr_reader :pointer

    sig { returns(String) }
    attr_reader :detail

    sig { params(detail: String, pointer: String).void }
    def initialize(detail, pointer: "")
      @detail = detail
      @pointer = pointer
      super(pointer.empty? ? detail : "#{pointer}: #{detail}")
    end

    sig { params(pointer: String).returns(DecodeError) }
    def at(pointer)
      return self unless @pointer.empty?

      DecodeError.new(detail, pointer: pointer)
    end
  end
end
