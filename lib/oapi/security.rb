# typed: strict
# frozen_string_literal: true

module Oapi
  module Security
    # One alternative from a document's `security`: every scheme in it must be satisfied.
    # An empty one is the spec's way of saying the endpoint may also be reached
    # anonymously.
    class Requirement < T::Struct
      extend T::Sig

      const :schemes, T::Hash[String, T::Array[String]]

      sig { returns(T::Boolean) }
      def anonymous? = schemes.empty?
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
    end

    class Http < T::Struct
      include Scheme
      const :name, String
      const :scheme, String
      const :bearer_format, T.nilable(String), default: nil
    end

    class OAuth2 < T::Struct
      include Scheme
      const :name, String
      const :scopes, T::Hash[String, String], default: {}
    end

    class OpenIdConnect < T::Struct
      include Scheme
      const :name, String
      const :url, String
    end
  end
end
