# typed: strict
# frozen_string_literal: true

module Oapi
  module Codable
    extend T::Sig
    extend T::Helpers
    interface!

    module ClassMethods
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.params(value: Oapi::Wire).returns(T.attached_class) }
      def from_openapi(value); end
    end

    mixes_in_class_methods(ClassMethods)

    sig { abstract.returns(Oapi::Wire) }
    def to_openapi; end
  end
end
