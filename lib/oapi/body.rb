# typed: strict
# frozen_string_literal: true

require "stringio"
require "tempfile"

require "oapi/wire"

module Oapi
  Stream = T.type_alias { T.any(::IO, ::StringIO, ::Tempfile) }

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

    class Binary
      extend T::Sig
      include Body

      sig { returns(Oapi::Stream) }
      attr_reader :stream

      sig { returns(::Integer) }
      attr_reader :chunk

      sig { params(stream: Oapi::Stream, chunk: ::Integer).void }
      def initialize(stream:, chunk: Oapi::DEFAULT_CHUNK)
        raise ArgumentError, "chunk must be positive, got #{chunk}" unless chunk.positive?

        @stream = stream
        @chunk = chunk
      end

      # Rack iterates the body once and its close does not reach here, so the stream is
      # closed when iteration ends, whether that is exhaustion or the client vanishing.
      sig { params(block: T.proc.params(bytes: ::String).void).void }
      def each(&block)
        while (bytes = stream.read(chunk))
          block.call(bytes)
        end
      ensure
        stream.close if stream.respond_to?(:close) && !stream.closed?
      end
    end
  end
end
