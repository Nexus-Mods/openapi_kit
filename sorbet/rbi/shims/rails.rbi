# typed: strong

module ActionDispatch
  class Request; end

  module Http
    class UploadedFile
      sig { returns(String) }
      def original_filename; end

      sig { returns(T.nilable(String)) }
      def content_type; end

      sig { returns(T.untyped) }
      def tempfile; end
    end
  end
end

module Rack
  class Request; end
end
