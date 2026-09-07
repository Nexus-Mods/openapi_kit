# typed: strict
# frozen_string_literal: true

module Oapi
  # The parsed value model every supported media type leaves behind: application/json and
  # +json, form-urlencoded, and a multipart body's text fields all arrive as these shapes,
  # as do path, query and header values. A codec converts between one of them and a Ruby
  # type, both ways. An uploaded file is the one thing outside it, so it never reaches a
  # codec.
  Wire = T.type_alias do
    T.any(NilClass, String, Integer, Float, T::Boolean,
          T::Array[T.untyped], T::Hash[String, T.untyped])
  end
end
