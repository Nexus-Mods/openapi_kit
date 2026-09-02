# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Model
      class HttpMethod < T::Enum
        enums do
          Get     = new("get")
          Put     = new("put")
          Post    = new("post")
          Delete  = new("delete")
          Options = new("options")
          Head    = new("head")
          Patch   = new("patch")
          Trace   = new("trace")
        end
      end

      class PathStyle < T::Enum
        enums do
          Simple = new("simple")
          Label  = new("label")
          Matrix = new("matrix")
        end
      end

      class QueryStyle < T::Enum
        enums do
          Form           = new("form")
          SpaceDelimited = new("spaceDelimited")
          PipeDelimited  = new("pipeDelimited")
          DeepObject     = new("deepObject")
        end
      end

      class ParameterInfo < T::Struct
        const :name, String
        const :identifier, Symbol
        const :schema, Schema
        const :description, T.nilable(String), default: nil
        const :deprecated, T::Boolean, default: false
      end

      module Parameter
        extend T::Sig
        extend T::Helpers
        include Kernel
        sealed!

        sig { params(parameter: Parameter).returns(ParameterInfo) }
        def self.info(parameter)
          case parameter
          when PathParameter, QueryParameter, HeaderParameter, CookieParameter then parameter.info
          else T.absurd(parameter)
          end
        end

        sig { params(parameter: Parameter).returns(T::Boolean) }
        def self.required?(parameter)
          case parameter
          when PathParameter then true
          when QueryParameter, HeaderParameter, CookieParameter then parameter.required
          else T.absurd(parameter)
          end
        end
      end

      class PathParameter < T::Struct
        include Parameter
        const :info, ParameterInfo
        const :style, PathStyle, default: PathStyle::Simple
        const :explode, T::Boolean, default: false
      end

      class QueryParameter < T::Struct
        include Parameter
        const :info, ParameterInfo
        const :required, T::Boolean, default: false
        const :style, QueryStyle, default: QueryStyle::Form
        const :explode, T::Boolean, default: true
        const :allow_reserved, T::Boolean, default: false
      end

      class HeaderParameter < T::Struct
        include Parameter
        const :info, ParameterInfo
        const :required, T::Boolean, default: false
        const :explode, T::Boolean, default: false
      end

      class CookieParameter < T::Struct
        include Parameter
        const :info, ParameterInfo
        const :required, T::Boolean, default: false
        const :explode, T::Boolean, default: true
      end

      class Content < T::Struct
        const :media_type, String
        const :schema, T.nilable(Schema), default: nil
      end

      class RequestBody < T::Struct
        const :contents, T::Array[Content]
        const :required, T::Boolean, default: false
        const :description, T.nilable(String), default: nil
      end

      class Header < T::Struct
        const :name, String
        const :identifier, Symbol
        const :schema, Schema
        const :required, T::Boolean, default: false
        const :description, T.nilable(String), default: nil
      end

      module Status
        extend T::Sig
        extend T::Helpers
        include Kernel
        sealed!

        NAMES = T.let(
          {
            200 => "Ok", 201 => "Created", 202 => "Accepted", 203 => "NonAuthoritativeInformation",
            204 => "NoContent", 205 => "ResetContent", 206 => "PartialContent",
            301 => "MovedPermanently", 302 => "Found", 303 => "SeeOther", 304 => "NotModified",
            307 => "TemporaryRedirect", 308 => "PermanentRedirect",
            400 => "BadRequest", 401 => "Unauthorized", 402 => "PaymentRequired", 403 => "Forbidden",
            404 => "NotFound", 405 => "MethodNotAllowed", 406 => "NotAcceptable", 409 => "Conflict",
            410 => "Gone", 412 => "PreconditionFailed", 413 => "ContentTooLarge",
            415 => "UnsupportedMediaType", 418 => "ImATeapot", 422 => "UnprocessableContent",
            425 => "TooEarly", 428 => "PreconditionRequired", 429 => "TooManyRequests",
            500 => "InternalServerError", 501 => "NotImplemented", 502 => "BadGateway",
            503 => "ServiceUnavailable", 504 => "GatewayTimeout"
          }.freeze,
          T::Hash[Integer, String]
        )

        sig { params(status: Status).returns(String) }
        def self.constant(status)
          case status
          when StatusCode then NAMES[status.code] || "Status#{status.code}"
          when StatusRange then "Status#{status.hundreds}xx"
          when DefaultStatus then "Default"
          else T.absurd(status)
          end
        end

        sig { params(raw: String).returns(Status) }
        def self.parse(raw)
          return DefaultStatus.new if raw == "default"
          return StatusRange.new(hundreds: T.must(raw[0]).to_i) if raw.match?(/\A[1-5]XX\z/i)
          return StatusCode.new(code: raw.to_i) if raw.match?(/\A[1-5]\d\d\z/)

          raise SchemaError,
                "#{raw.inspect} is not a valid response status. Use a three-digit code " \
                "(200), a range (4XX) or `default`."
        end
      end

      module SecurityScheme
        extend T::Sig
        extend T::Helpers
        include Kernel
        sealed!

        sig { params(scheme: SecurityScheme).returns(String) }
        def self.name_of(scheme)
          case scheme
          when ApiKeyScheme, HttpScheme, OAuth2Scheme, OpenIdConnectScheme then scheme.name
          else T.absurd(scheme)
          end
        end
      end

      class StatusCode < T::Struct
        include Status
        const :code, Integer
      end

      class StatusRange < T::Struct
        include Status
        const :hundreds, Integer
      end

      class DefaultStatus < T::Struct
        include Status
      end

      class Response < T::Struct
        const :status, Status
        const :contents, T::Array[Content]
        const :headers, T::Array[Header], default: []
        const :description, T.nilable(String), default: nil
      end

      class SecurityRequirement < T::Struct
        extend T::Sig
        const :schemes, T::Hash[String, T::Array[String]]

        sig { returns(T::Boolean) }
        def anonymous? = schemes.empty?
      end

      class ApiKeyLocation < T::Enum
        enums do
          Query  = new("query")
          Header = new("header")
          Cookie = new("cookie")
        end
      end

      class ApiKeyScheme < T::Struct
        include SecurityScheme
        const :name, String
        const :location, ApiKeyLocation
        const :parameter_name, String
        const :description, T.nilable(String), default: nil
      end

      class HttpScheme < T::Struct
        include SecurityScheme
        const :name, String
        const :scheme, String
        const :bearer_format, T.nilable(String), default: nil
        const :description, T.nilable(String), default: nil
      end

      class OAuth2Scheme < T::Struct
        include SecurityScheme
        const :name, String
        const :scopes, T::Hash[String, String], default: {}
        const :description, T.nilable(String), default: nil
      end

      class OpenIdConnectScheme < T::Struct
        include SecurityScheme
        const :name, String
        const :url, String
        const :description, T.nilable(String), default: nil
      end

      class Operation < T::Struct
        extend T::Sig
        const :id, String
        const :http_method, HttpMethod
        const :path, String
        const :tag, String
        const :parameters, T::Array[Parameter], default: []
        const :request_body, T.nilable(RequestBody), default: nil
        const :responses, T::Array[Response], default: []
        const :security, T.nilable(T::Array[SecurityRequirement]), default: nil
        const :summary, T.nilable(String), default: nil
        const :description, T.nilable(String), default: nil
        const :deprecated, T::Boolean, default: false
        const :extensions, T::Hash[String, T.untyped], default: {}
      end

      class Document < T::Struct
        extend T::Sig
        const :title, String
        const :version, String
        const :types, T::Array[TypeDef], default: []
        const :operations, T::Array[Operation], default: []
        const :security_schemes, T::Array[SecurityScheme], default: []
        const :security, T::Array[SecurityRequirement], default: []

        # An operation that declares no security inherits the document's.
        sig { params(operation: Operation).returns(T::Array[SecurityRequirement]) }
        def security_for(operation) = operation.security || security
        const :raw, T::Hash[String, T.untyped], default: {}

        sig { returns(T::Array[String]) }
        def tags = operations.map(&:tag).uniq
      end
    end
  end
end
