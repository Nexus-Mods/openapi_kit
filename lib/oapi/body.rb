# typed: strict
# frozen_string_literal: true

require "pathname"

require "oapi/wire"

module Oapi
  class Sink
    extend T::Sig

    sig { params(block: T.proc.params(bytes: ::String).void).void }
    def initialize(block)
      @block = block
    end

    sig { params(bytes: ::String).returns(::Integer) }
    def write(bytes)
      @block.call(bytes.b)
      bytes.bytesize
    end

    sig { params(bytes: ::String).returns(T.self_type) }
    def <<(bytes)
      write(bytes)
      self
    end

    sig { returns(T.self_type) }
    def flush = self
  end

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

    class Stream < T::Struct
      extend T::Sig
      include Body

      const :body, T.proc.params(sink: Oapi::Sink).void

      sig { params(block: T.proc.params(bytes: ::String).void).void }
      def each(&block) = body.call(Sink.new(block))
    end

    class File < T::Struct
      extend T::Sig
      include Body

      const :path, ::Pathname

      sig { returns(::Integer) }
      def size = path.size
    end

    Bytes = T.type_alias { T.any(Oapi::Body::Stream, Oapi::Body::File) }
  end
end
