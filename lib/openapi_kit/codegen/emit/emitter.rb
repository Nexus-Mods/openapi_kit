# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      module Emitter
        extend T::Sig
        extend T::Helpers
        interface!

        sig { abstract.returns(T::Array[SourceFile]) }
        def render; end
      end
    end
  end
end
