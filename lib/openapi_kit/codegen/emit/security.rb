# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class Security
        extend T::Sig
        include Emitter

        sig { params(document: Model::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { params(name: String).returns(String) }
        def self.constant(name) = Naming.snake(name).upcase

        sig { params(name: String).returns(String) }
        def self.module_name(name) = Naming.pascal(name)

        # The principal a protected operation carries. An anonymous alternative means the
        # request may arrive without one.
        sig do
          params(requirements: T::Array[Model::SecurityRequirement], config: Config).returns(String)
        end
        def self.principal_type(requirements, config)
          type = T.must(config.principal)
          requirements.any?(&:anonymous?) ? "T.nilable(#{type})" : type
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if @document.security_schemes.empty?

          [
            Source.file(path: "#{@config.module_path}/security.rb",
                        modules: @config.modules + ["Security"]) { |buffer| emit_body(buffer) }
          ]
        end

        private

        sig { params(buffer: Buffer).void }
        def emit_body(buffer)
          buffer.line("extend T::Sig")

          @document.security_schemes.each do |scheme|
            buffer.blank
            buffer.line("#{Security.constant(Model::SecurityScheme.name_of(scheme))} = T.let(")
            buffer.indent do
              type, arguments = constructor(scheme)
              extensions = Model::SecurityScheme.extensions_of(scheme)
              arguments += [["extensions", extensions.inspect]] unless extensions.empty?
              buffer.nest_call("#{type}.new", arguments)
              buffer.line(type)
            end
            buffer.line(")")
          end

          buffer.blank
          emit_catalogue(buffer)

          authenticated.each do |scheme|
            buffer.blank
            emit_authenticator(buffer, scheme)
          end
        end

        # One interface per scheme, filled by a registry slot the same way handlers are.
        # Returning nil means this alternative was not satisfied, so the next one is
        # tried. Raise to refuse outright.
        sig { params(buffer: Buffer, scheme: Model::SecurityScheme).void }
        def emit_authenticator(buffer, scheme)
          name = Model::SecurityScheme.name_of(scheme)

          type, = constructor(scheme)

          buffer.nest("module #{Security.module_name(name)}") do
            buffer.line("extend T::Sig")
            buffer.line("extend T::Helpers")
            buffer.line("abstract!")
            buffer.blank
            buffer.line("sig { returns(#{type}) }")
            buffer.line("def scheme = #{Security.constant(name)}")
            buffer.blank
            emit_credential(buffer, scheme)
            buffer.blank
            emit_authenticate(buffer)
          end
        end

        sig { params(buffer: Buffer, scheme: Model::SecurityScheme).void }
        def emit_credential(buffer, scheme)
          buffer.line("sig { params(request: ::ActionDispatch::Request).returns(T.nilable(::String)) }")
          buffer.line("def credential(request) = ::OpenAPIKit::Security.credential(scheme, request)")
          return unless basic?(scheme)

          buffer.blank
          buffer.line("sig do")
          buffer.indent do
            buffer.line("params(request: ::ActionDispatch::Request)")
            buffer.line("  .returns(T.nilable([::String, ::String]))")
          end
          buffer.line("end")
          buffer.line("def basic_credential(request) = ::OpenAPIKit::Security.basic(scheme, request)")
        end

        sig { params(buffer: Buffer).void }
        def emit_authenticate(buffer)
          buffer.line("sig do")
          buffer.indent do
            buffer.line("abstract.params(request: ::ActionDispatch::Request, scopes: T::Array[::String])")
            buffer.line("        .returns(T.nilable(#{T.must(@config.principal)}))")
          end
          buffer.line("end")
          buffer.line("def authenticate(request:, scopes:); end")
        end

        # Undecoded base64 is no use, so a basic scheme gets the decoded pair instead.
        sig { params(scheme: Model::SecurityScheme).returns(T::Boolean) }
        def basic?(scheme) = scheme.is_a?(Model::HttpScheme) && scheme.scheme == "basic"

        sig { params(name: String).returns(T::Boolean) }
        def used?(name)
          @document.operations.any? do |operation|
            @document.security_for(operation).any? { |requirement| requirement.schemes.key?(name) }
          end
        end

        sig { returns(T::Array[Model::SecurityScheme]) }
        def authenticated
          return [] if @config.principal.nil?

          @document.security_schemes.select { |scheme| used?(Model::SecurityScheme.name_of(scheme)) }
        end

        sig { params(buffer: Buffer).void }
        def emit_catalogue(buffer)
          buffer.line("SCHEMES = T.let(")
          buffer.indent do
            buffer.line("{")
            buffer.indent do
              @document.security_schemes.each do |scheme|
                name = Model::SecurityScheme.name_of(scheme)
                buffer.line("#{name.inspect} => #{Security.constant(name)},")
              end
            end
            buffer.line("}.freeze,")
            buffer.line("T::Hash[::String, ::OpenAPIKit::Security::Scheme]")
          end
          buffer.line(")")
        end

        sig do
          params(scheme: Model::SecurityScheme)
            .returns([String, T::Array[[String, String]]])
        end
        def constructor(scheme)
          case scheme
          when Model::ApiKeyScheme
            location = "::OpenAPIKit::Security::ApiKeyLocation::#{Naming.pascal(scheme.location.serialize)}"
            ["::OpenAPIKit::Security::ApiKey",
             [["name", scheme.name.inspect], ["location", location],
              ["parameter_name", scheme.parameter_name.inspect]]]
          when Model::HttpScheme
            ["::OpenAPIKit::Security::Http",
             [["name", scheme.name.inspect], ["scheme", scheme.scheme.inspect],
              ["bearer_format", scheme.bearer_format.inspect]]]
          when Model::OAuth2Scheme
            ["::OpenAPIKit::Security::OAuth2",
             [["name", scheme.name.inspect], ["scopes", scheme.scopes.inspect]]]
          when Model::OpenIdConnectScheme
            ["::OpenAPIKit::Security::OpenIdConnect",
             [["name", scheme.name.inspect], ["url", scheme.url.inspect]]]
          else T.absurd(scheme)
          end
        end
      end
    end
  end
end
