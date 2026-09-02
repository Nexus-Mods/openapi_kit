# typed: strict
# frozen_string_literal: true

module Oapi
  class UploadedFile < T::Struct
    const :io, T.untyped
    const :filename, T.nilable(String), default: nil
    const :content_type, T.nilable(String), default: nil
  end
end
