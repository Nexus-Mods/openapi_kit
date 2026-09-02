# typed: strict
# frozen_string_literal: true

require "action_dispatch"

module Oapi
  module Wire
    # What a codec may return: JSON, and nothing that cannot be rendered as JSON.
    Out = T.type_alias do
      T.any(NilClass, String, Integer, Float, T::Boolean,
            T::Array[T.untyped], T::Hash[String, T.untyped])
    end

    # What a codec may receive. A multipart body arrives already parsed, so a value can
    # also be a file Rails wrote to disk, which is not renderable and so not an Out.
    In = T.type_alias { T.any(Out, ::ActionDispatch::Http::UploadedFile) }
  end
end
