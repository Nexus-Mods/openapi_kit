# typed: strict
# frozen_string_literal: true

class FileCodec
  extend T::Sig
  extend T::Generic
  include Oapi::Codec::Contract

  Value = type_member { { fixed: ::ActionDispatch::Http::UploadedFile } }

  sig { override.params(value: Oapi::Wire).returns(::ActionDispatch::Http::UploadedFile) }
  def from_wire(value)
    return value if value.is_a?(::ActionDispatch::Http::UploadedFile)

    raise Oapi::DecodeError, "expected an uploaded file"
  end

  sig { override.params(value: ::ActionDispatch::Http::UploadedFile).returns(Oapi::Wire) }
  def to_wire(value) = value.original_filename
end
