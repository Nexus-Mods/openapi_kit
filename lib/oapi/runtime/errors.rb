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

    sig { params(prefix: String).returns(DecodeError) }
    def at(prefix)
      DecodeError.new(detail, pointer: "#{prefix}#{@pointer}")
    end
  end
end
