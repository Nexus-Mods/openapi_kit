# typed: strict
# frozen_string_literal: true

require "stringio"

require "oapi/wire"

module Oapi
  Stream = T.type_alias { T.any(::IO, ::StringIO) }

  DEFAULT_CHUNK = 16_384

  module Body
    extend T::Sig
    extend T::Helpers
    abstract!
    sealed!

    class Empty < T::Struct
      include Body
    end

    class Json < T::Struct
      include Body

      const :wire, Oapi::Wire
    end

    class Binary < T::Struct
      extend T::Sig
      include Body

      const :stream, Oapi::Stream
      const :chunk, ::Integer, default: Oapi::DEFAULT_CHUNK

      sig { params(block: T.proc.params(bytes: ::String).void).void }
      def each(&block)
        raise ArgumentError, "chunk must be positive, got #{chunk}" unless chunk.positive?

        while (bytes = stream.read(chunk))
          block.call(bytes)
        end
      end
    end
  end
end
