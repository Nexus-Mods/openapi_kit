# typed: strong

module Prism
  sig { params(source: String).returns(Prism::ParseResult) }
  def self.parse(source); end

  module LexCompat
    class Result; end
  end

  class Location
    sig { returns(Integer) }
    def start_line; end
  end

  class ParseError
    sig { returns(String) }
    def message; end

    sig { returns(Prism::Location) }
    def location; end
  end

  class ParseResult
    sig { returns(T::Boolean) }
    def success?; end

    sig { returns(T::Array[Prism::ParseError]) }
    def errors; end
  end
end
