# typed: strict
# frozen_string_literal: true

module Oapi
  # What a codec may return: JSON, and nothing that cannot be rendered as JSON. There is
  # no matching type for what a codec receives, because that is whatever the framework
  # hands over, and coercing it to the declared type is the codec's whole job.
  Wire = T.type_alias do
    T.any(NilClass, String, Integer, Float, T::Boolean,
          T::Array[T.untyped], T::Hash[String, T.untyped])
  end
end
