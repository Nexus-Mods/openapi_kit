# typed: strict
# frozen_string_literal: true

require "action_dispatch"

require "oapi/wire"

module Oapi
  module Form
    Parts = T.type_alias do
      T::Hash[::String, T.any(Oapi::Wire, ::ActionDispatch::Http::UploadedFile)]
    end

    module Contract
      extend T::Sig
      extend T::Generic
      interface!

      Value = type_member

      sig { abstract.params(parts: Oapi::Form::Parts).returns(Value) }
      def from_parts(parts); end
    end
  end
end
