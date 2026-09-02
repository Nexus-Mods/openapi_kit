# typed: strict
# frozen_string_literal: true

module Oapi
  module Emit
    module Ruby
      extend T::Sig

      class Expr < T::Struct
        const :code, String
      end

      sig { params(code: String).returns(Expr) }
      def self.expr(code) = Expr.new(code: code)

      sig { params(parts: T.any(String, Expr)).returns(String) }
      def self.string(*parts)
        body = parts.map do |part|
          case part
          when Expr then "\#{#{part.code}}"
          else escape(part)
          end
        end

        %("#{body.join}")
      end

      sig { params(text: String).returns(String) }
      def self.escape(text)
        text.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("#", "\\#")
      end
    end
  end
end
