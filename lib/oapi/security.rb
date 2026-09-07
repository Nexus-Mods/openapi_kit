# typed: strict
# frozen_string_literal: true

module Oapi
  module Security
    extend T::Sig

    sig do
      type_parameters(:Principal)
        .params(attempts: T::Array[T.proc.returns(T.nilable(T.type_parameter(:Principal)))])
        .returns(T.nilable(T.type_parameter(:Principal)))
    end
    def self.first_of(attempts) = attempts.lazy.filter_map(&:call).first

    sig { params(scheme: Scheme, request: T.untyped).returns(T.nilable(String)) }
    def self.credential(scheme, request)
      case scheme
      when ApiKey then api_key(scheme, request)
      when Http then authorization(request, scheme.scheme)
      when OAuth2, OpenIdConnect then authorization(request, "bearer")
      else T.absurd(scheme)
      end
    end

    sig { params(scheme: Http, request: T.untyped).returns(T.nilable([String, String])) }
    def self.basic(scheme, request)
      encoded = credential(scheme, request)
      return nil if encoded.nil?

      decoded = begin
        encoded.unpack1("m0")
      rescue ArgumentError
        nil
      end
      user, password = decoded.to_s.split(":", 2)
      user.nil? || password.nil? ? nil : [user, password]
    end

    sig { params(scheme: ApiKey, request: T.untyped).returns(T.nilable(String)) }
    def self.api_key(scheme, request)
      location = scheme.location
      case location
      when ApiKeyLocation::Header then present(request.headers[scheme.parameter_name])
      when ApiKeyLocation::Query then present(request.query_parameters[scheme.parameter_name])
      when ApiKeyLocation::Cookie then present(request.cookies[scheme.parameter_name])
      else T.absurd(location)
      end
    end

    sig { params(request: T.untyped, scheme: String).returns(T.nilable(String)) }
    def self.authorization(request, scheme)
      header = present(request.headers["Authorization"])
      return nil if header.nil?

      prefix = "#{scheme} "
      return nil unless header.downcase.start_with?(prefix.downcase)

      present(header[prefix.length..])
    end

    sig { params(value: T.untyped).returns(T.nilable(String)) }
    def self.present(value)
      string = value.to_s
      string.empty? ? nil : string
    end

    module Scheme
      extend T::Sig
      extend T::Helpers
      include Kernel
      sealed!

      sig { params(scheme: Scheme).returns(String) }
      def self.name_of(scheme)
        case scheme
        when ApiKey, Http, OAuth2, OpenIdConnect then scheme.name
        else T.absurd(scheme)
        end
      end
    end

    class ApiKeyLocation < T::Enum
      enums do
        Query  = new("query")
        Header = new("header")
        Cookie = new("cookie")
      end
    end

    class ApiKey < T::Struct
      include Scheme
      const :name, String
      const :location, ApiKeyLocation
      const :parameter_name, String
      const :extensions, T::Hash[String, T.untyped], default: {}
    end

    class Http < T::Struct
      include Scheme
      const :name, String
      const :scheme, String
      const :bearer_format, T.nilable(String), default: nil
      const :extensions, T::Hash[String, T.untyped], default: {}
    end

    class OAuth2 < T::Struct
      include Scheme
      const :name, String
      const :scopes, T::Hash[String, String], default: {}
      const :extensions, T::Hash[String, T.untyped], default: {}
    end

    class OpenIdConnect < T::Struct
      include Scheme
      const :name, String
      const :url, String
      const :extensions, T::Hash[String, T.untyped], default: {}
    end
  end
end
