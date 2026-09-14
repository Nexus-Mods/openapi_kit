# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      module Literal
        extend T::Sig

        class Expr < T::Struct
          const :code, String
        end

        sig { params(code: String).returns(Expr) }
        def self.expr(code) = Expr.new(code: code)

        sig { params(parts: T.any(String, Expr)).returns(String) }
        def self.string(*parts)
          body = parts.map do |part|
            part.is_a?(Expr) ? "\#{#{part.code}}" : T.must(part.dump[1..-2])
          end

          %("#{body.join}")
        end
      end
    end
  end
end
