# typed: strict
# frozen_string_literal: true

module Oapi
  Wire = T.type_alias do
    T.any(NilClass, String, Integer, Float, T::Boolean,
          T::Array[T.untyped], T::Hash[String, T.untyped])
  end
end
