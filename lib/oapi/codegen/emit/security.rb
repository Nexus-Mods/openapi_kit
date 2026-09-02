# typed: strict
# frozen_string_literal: true

module Oapi
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
              buffer.line("::Oapi::Security::Scheme")
            end
            buffer.line(")")
          end

          buffer.blank
          emit_catalogue(buffer)
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
            buffer.line("T::Hash[::String, ::Oapi::Security::Scheme]")
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
            location = "::Oapi::Security::ApiKeyLocation::#{Naming.pascal(scheme.location.serialize)}"
            ["::Oapi::Security::ApiKey",
             [["name", scheme.name.inspect], ["location", location],
              ["parameter_name", scheme.parameter_name.inspect]]]
          when Model::HttpScheme
            ["::Oapi::Security::Http",
             [["name", scheme.name.inspect], ["scheme", scheme.scheme.inspect],
              ["bearer_format", scheme.bearer_format.inspect]]]
          when Model::OAuth2Scheme
            ["::Oapi::Security::OAuth2",
             [["name", scheme.name.inspect], ["scopes", scheme.scopes.inspect]]]
          when Model::OpenIdConnectScheme
            ["::Oapi::Security::OpenIdConnect",
             [["name", scheme.name.inspect], ["url", scheme.url.inspect]]]
          else T.absurd(scheme)
          end
        end
      end
    end
  end
end
