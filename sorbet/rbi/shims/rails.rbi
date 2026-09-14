# typed: strong

module ActionDispatch
  class Request
    sig { returns(T.untyped) }
    def headers; end

    sig { returns(T::Hash[String, String]) }
    def cookies; end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def path_parameters; end

    sig { returns(T::Hash[String, T.untyped]) }
    def query_parameters; end

    sig { returns(T::Hash[String, T.untyped]) }
    def request_parameters; end
  end

  class Response
    sig { returns(T::Hash[String, T.untyped]) }
    def headers; end

    sig { params(status: Integer).void }
    def status=(status); end

    sig { params(path: String).void }
    def send_file(path); end
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
      sig { params(path: String, to: String, format: T::Boolean).void }
      def get(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def post(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def put(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def patch(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def delete(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def options(path, to:, format: true); end

      sig { params(path: String, to: String, format: T::Boolean).void }
      def head(path, to:, format: true); end
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

    sig { returns(ActionDispatch::Response) }
    def response; end

    sig { params(body: T.untyped).void }
    def response_body=(body); end
  end
end

module ActiveSupport
  module Concern
    sig { params(block: T.proc.bind(T.untyped).void).void }
    def included(&block); end
  end
end
