# typed: strict
# frozen_string_literal: true

class FileCodec
  extend T::Sig
  extend T::Generic
  include OpenAPIKit::Codec::Contract

  Value = type_member { { fixed: ::ActionDispatch::Http::UploadedFile } }

  sig { override.params(value: OpenAPIKit::Wire).returns(::ActionDispatch::Http::UploadedFile) }
  def from_wire(value)
    return value if value.is_a?(::ActionDispatch::Http::UploadedFile)

    raise OpenAPIKit::DecodeError, "expected an uploaded file"
  end

  sig { override.params(value: ::ActionDispatch::Http::UploadedFile).returns(OpenAPIKit::Wire) }
  def to_wire(value) = value.original_filename
end
