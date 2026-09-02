# typed: strong
#
# openapi3_parser ships no type information. This declares the node surface the loader
# actually touches, so the one place parser objects are handled is checked like the rest
# of the generator. Types follow the gem's own documented return values; predicates are
# nilable because a field absent from the document has no value to normalise.

module Openapi3Parser
  sig { params(path: T.any(String, Pathname)).returns(Openapi3Parser::Document) }
  def self.load_file(path); end

  sig { params(input: T.untyped).returns(Openapi3Parser::Document) }
  def self.load(input); end

  class Document
    sig { returns(T::Boolean) }
    def valid?; end

    sig { returns(T::Array[Openapi3Parser::Validation::Error]) }
    def errors; end

    sig { returns(Openapi3Parser::Node::Info) }
    def info; end

    sig { returns(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::PathItem]) }
    def paths; end

    sig { returns(T.nilable(Openapi3Parser::Node::Components)) }
    def components; end

    sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::SecurityRequirement])) }
    def security; end

    sig { returns(Openapi3Parser::Node::Context) }
    def node_context; end
  end

  module Validation
    class Error
      sig { returns(T.nilable(Openapi3Parser::Node::Context)) }
      def context; end

      sig { returns(String) }
      def message; end
    end
  end

  class Source
    sig { returns(Openapi3Parser::SourceInput) }
    def source_input; end

    class Location
      sig { returns(Openapi3Parser::Source::Pointer) }
      def pointer; end

      sig { returns(Openapi3Parser::Source) }
      def source; end
    end

    class Pointer
      sig { returns(T::Array[T.untyped]) }
      def segments; end
    end
  end

  class SourceInput
    sig { returns(T.untyped) }
    def path; end
  end

  module Node
    class Object
      sig { returns(Openapi3Parser::Node::Context) }
      def node_context; end
    end

    class Context
      sig { returns(T.untyped) }
      def input; end

      sig { returns(Openapi3Parser::Source::Location) }
      def source_location; end

      sig { returns(T.nilable(String)) }
      def location_summary; end
    end

    class Array
      extend T::Generic
      Elem = type_member

      sig { returns(T::Array[Elem]) }
      def to_a; end

      sig { returns(T.nilable(Elem)) }
      def first; end

      sig { returns(T::Boolean) }
      def empty?; end

      sig { returns(T::Boolean) }
      def any?; end

      sig { returns(Integer) }
      def size; end

      sig { params(index: Integer).returns(T.nilable(Elem)) }
      def [](index); end

      sig { params(block: T.proc.params(item: Elem).void).void }
      def each(&block); end

      sig do
        type_parameters(:Result)
          .params(block: T.proc.params(item: Elem).returns(T.type_parameter(:Result)))
          .returns(T::Array[T.type_parameter(:Result)])
      end
      def map(&block); end

      sig { returns(T::Enumerator[[Elem, Integer]]) }
      def each_with_index; end
    end

    class Map
      extend T::Generic
      K = type_member
      V = type_member

      sig { returns(T::Array[K]) }
      def keys; end

      sig { returns(T::Array[V]) }
      def values; end

      sig { returns(T::Boolean) }
      def empty?; end

      sig { returns(T::Boolean) }
      def any?; end

      sig { returns(Integer) }
      def size; end

      sig { params(key: T.any(String, Symbol)).returns(T.nilable(V)) }
      def [](key); end

      sig do
        type_parameters(:Key, :Value)
          .params(block: T.proc.params(key: K, value: V)
                          .returns([T.type_parameter(:Key), T.type_parameter(:Value)]))
          .returns(T::Hash[T.type_parameter(:Key), T.type_parameter(:Value)])
      end
      def to_h(&block); end

      sig { params(block: T.proc.params(key: K, value: V).void).void }
      def each(&block); end

      sig do
        type_parameters(:Result)
          .params(block: T.proc.params(key: K, value: V).returns(T.type_parameter(:Result)))
          .returns(T::Array[T.type_parameter(:Result)])
      end
      def map(&block); end

      sig do
        type_parameters(:Result)
          .params(block: T.proc.params(key: K, value: V).returns(T::Array[T.type_parameter(:Result)]))
          .returns(T::Array[T.type_parameter(:Result)])
      end
      def flat_map(&block); end
    end

    class Info < Openapi3Parser::Node::Object
      sig { returns(String) }
      def title; end

      sig { returns(String) }
      def version; end
    end

    class Components < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::Schema])) }
      def schemas; end

      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::SecurityScheme])) }
      def security_schemes; end
    end

    class PathItem < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::Parameter])) }
      def parameters; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def get; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def put; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def post; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def delete; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def options; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def head; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def patch; end

      sig { returns(T.nilable(Openapi3Parser::Node::Operation)) }
      def trace; end
    end

    class Operation < Openapi3Parser::Node::Object
      sig { returns(T.nilable(String)) }
      def operation_id; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[String])) }
      def tags; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::Parameter])) }
      def parameters; end

      sig { returns(T.nilable(Openapi3Parser::Node::RequestBody)) }
      def request_body; end

      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::Response])) }
      def responses; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::SecurityRequirement])) }
      def security; end

      sig { returns(T.nilable(String)) }
      def summary; end

      sig { returns(T.nilable(String)) }
      def description; end

      sig { returns(T.nilable(T::Boolean)) }
      def deprecated?; end

    end

    class SecurityRequirement < Openapi3Parser::Node::Object
      sig { returns(T::Hash[String, T.untyped]) }
      def to_h; end
    end

    class Parameter < Openapi3Parser::Node::Object
      sig { returns(String) }
      def name; end

      sig { returns(String) }
      def in; end

      sig { returns(T.nilable(T::Boolean)) }
      def required?; end

      sig { returns(T.nilable(String)) }
      def style; end

      sig { returns(T.nilable(T::Boolean)) }
      def explode?; end

      sig { returns(T.nilable(T::Boolean)) }
      def allow_reserved?; end

      sig { returns(T.nilable(Openapi3Parser::Node::Schema)) }
      def schema; end

      sig { returns(T.nilable(String)) }
      def description; end

      sig { returns(T.nilable(T::Boolean)) }
      def deprecated?; end

    end

    class RequestBody < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::MediaType])) }
      def content; end

      sig { returns(T.nilable(T::Boolean)) }
      def required?; end

      sig { returns(T.nilable(String)) }
      def description; end
    end

    class Response < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::MediaType])) }
      def content; end

      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::Header])) }
      def headers; end

      sig { returns(T.nilable(String)) }
      def description; end
    end

    class MediaType < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Schema)) }
      def schema; end
    end

    class Header < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Schema)) }
      def schema; end

      sig { returns(T.nilable(T::Boolean)) }
      def required?; end

      sig { returns(T.nilable(String)) }
      def description; end
    end

    class Discriminator < Openapi3Parser::Node::Object
      sig { returns(String) }
      def property_name; end

      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, String])) }
      def mapping; end
    end

    class SecurityScheme < Openapi3Parser::Node::Object
      sig { returns(T.nilable(String)) }
      def type; end

      sig { returns(T.nilable(String)) }
      def name; end

      sig { returns(T.nilable(String)) }
      def in; end

      sig { returns(T.nilable(String)) }
      def scheme; end

      sig { returns(T.nilable(String)) }
      def bearer_format; end

      sig { returns(T.nilable(Openapi3Parser::Node::OauthFlows)) }
      def flows; end

      sig { returns(T.nilable(String)) }
      def open_id_connect_url; end

      sig { returns(T.nilable(String)) }
      def description; end
    end

    class OauthFlows < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::OauthFlow)) }
      def implicit; end

      sig { returns(T.nilable(Openapi3Parser::Node::OauthFlow)) }
      def password; end

      sig { returns(T.nilable(Openapi3Parser::Node::OauthFlow)) }
      def client_credentials; end

      sig { returns(T.nilable(Openapi3Parser::Node::OauthFlow)) }
      def authorization_code; end
    end

    class OauthFlow < Openapi3Parser::Node::Object
      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, String])) }
      def scopes; end
    end

    class Schema < Openapi3Parser::Node::Object
      sig { returns(T.nilable(String)) }
      def name; end

      sig { returns(T.nilable(String)) }
      def type; end

      sig { returns(T.nilable(String)) }
      def format; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[T.untyped])) }
      def enum; end

      sig { returns(T.untyped) }
      def default; end

      sig { returns(T.nilable(T::Boolean)) }
      def nullable?; end

      sig { returns(T.nilable(T::Boolean)) }
      def deprecated?; end

      sig { returns(T.nilable(T::Boolean)) }
      def read_only?; end

      sig { returns(T.nilable(T::Boolean)) }
      def write_only?; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::Schema])) }
      def all_of; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::Schema])) }
      def one_of; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[Openapi3Parser::Node::Schema])) }
      def any_of; end

      sig { returns(T.nilable(Openapi3Parser::Node::Schema)) }
      def items; end

      sig { returns(T.nilable(Openapi3Parser::Node::Map[String, Openapi3Parser::Node::Schema])) }
      def properties; end

      sig { returns(T.nilable(Openapi3Parser::Node::Array[String])) }
      def required; end

      sig { returns(T.nilable(Openapi3Parser::Node::Schema)) }
      def additional_properties_schema; end

      sig { returns(T.nilable(Openapi3Parser::Node::Discriminator)) }
      def discriminator; end

      sig { returns(T.nilable(String)) }
      def description; end

      sig { returns(T.nilable(Integer)) }
      def min_length; end

      sig { returns(T.nilable(Integer)) }
      def max_length; end

      sig { returns(T.nilable(String)) }
      def pattern; end

      sig { returns(T.nilable(Integer)) }
      def minimum; end

      sig { returns(T.nilable(Integer)) }
      def maximum; end

      sig { returns(T.nilable(T::Boolean)) }
      def exclusive_minimum?; end

      sig { returns(T.nilable(T::Boolean)) }
      def exclusive_maximum?; end

      sig { returns(T.nilable(Numeric)) }
      def multiple_of; end

      sig { returns(T.nilable(Integer)) }
      def min_items; end

      sig { returns(T.nilable(Integer)) }
      def max_items; end

      sig { returns(T.nilable(T::Boolean)) }
      def unique_items?; end

      sig { returns(T.nilable(Integer)) }
      def min_properties; end

      sig { returns(T.nilable(Integer)) }
      def max_properties; end

    end
  end
end
