# typed: strict
# frozen_string_literal: true

module Oapi
  module Emit
    class Buffer
      extend T::Sig

      sig { void }
      def initialize
        @lines = T.let([], T::Array[String])
        @depth = T.let(0, Integer)
      end

      sig { params(text: String).returns(Buffer) }
      def line(text)
        @lines << (text.empty? ? "" : "#{"  " * @depth}#{text}")
        self
      end

      sig { returns(Buffer) }
      def blank
        @lines << "" unless @lines.last == ""
        self
      end

      sig { params(block: T.proc.void).returns(Buffer) }
      def indent(&block)
        @depth += 1
        block.call
        @depth -= 1
        self
      end

      sig { params(header: String, block: T.proc.void).returns(Buffer) }
      def nest(header, &block)
        line(header)
        indent(&block)
        line("end")
      end

      sig { params(headers: T::Array[String], block: T.proc.void).returns(Buffer) }
      def nest_all(headers, &block)
        if headers.empty?
          block.call
          return self
        end

        nest(T.must(headers.first)) { nest_all(T.must(headers[1..]), &block) }
      end

      sig { params(subject: String, block: T.proc.void).returns(Buffer) }
      def case_of(subject, &block)
        line("case #{subject}")
        block.call
        line("end")
      end

      sig { params(names: T::Array[String], block: T.proc.void).returns(Buffer) }
      def nest_modules(names, &block)
        nest_all(names.map { |name| "module #{name}" }, &block)
      end

      sig { returns(T::Boolean) }
      def empty? = @lines.empty?

      sig { returns(String) }
      def to_s = "#{@lines.join("\n").rstrip}\n"
    end
  end
end
