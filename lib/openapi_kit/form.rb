# typed: strict
# frozen_string_literal: true

require "action_dispatch"

require "openapi_kit/wire"

module OpenAPIKit
  module Form
    Parts = T.type_alias do
      T::Hash[::String, T.any(OpenAPIKit::Wire, ::ActionDispatch::Http::UploadedFile)]
    end

    module Contract
      extend T::Sig
      extend T::Generic
      interface!

      Value = type_member

      sig { abstract.params(parts: OpenAPIKit::Form::Parts).returns(Value) }
      def from_parts(parts); end
    end
  end
end
