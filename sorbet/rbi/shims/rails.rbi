# typed: strong

module ActionDispatch
  class Request
    sig { returns(T.untyped) }
    def headers; end

    sig { returns(T.untyped) }
    def cookie_jar; end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def path_parameters; end

    sig { returns(T::Hash[String, T.untyped]) }
    def query_parameters; end

    sig { returns(T::Hash[String, T.untyped]) }
    def request_parameters; end
  end

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

module Rails
  class Railtie
    sig { returns(T.untyped) }
    def self.config; end
  end
end

module ActionDispatch
  module Routing
    class Mapper
      sig { params(path: String, to: String).void }
      def get(path, to:); end

      sig { params(path: String, to: String).void }
      def post(path, to:); end

      sig { params(path: String, to: String).void }
      def put(path, to:); end

      sig { params(path: String, to: String).void }
      def patch(path, to:); end

      sig { params(path: String, to: String).void }
      def delete(path, to:); end

      sig { params(path: String, to: String).void }
      def options(path, to:); end

      sig { params(path: String, to: String).void }
      def head(path, to:); end
    end
  end
end

module ActionController
  class API
    sig { params(error: T.untyped, with: T.untyped).void }
    def self.rescue_from(error, with:); end

    sig { returns(ActionDispatch::Request) }
    def request; end

    sig { params(status: T.untyped).void }
    def head(status); end

    sig { params(json: T.untyped, status: T.untyped, content_type: T.untyped).void }
    def render(json:, status:, content_type:); end
  end
end

module ActiveSupport
  module Concern
    sig { params(block: T.proc.bind(T.untyped).void).void }
    def included(&block); end
  end
end
