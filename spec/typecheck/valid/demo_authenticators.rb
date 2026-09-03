# typed: strict
# frozen_string_literal: true

# `principal` names one type for the whole document, so every authenticator interface
# returns it. An authenticator may narrow its own signature to the variant it actually
# produces, since return types are covariant.
class DemoBearerAuthenticator
  extend T::Sig
  include Server::Security::BearerAuth

  sig do
    override.params(request: ActionDispatch::Request, scopes: T::Array[String])
            .returns(T.nilable(Demo::User))
  end
  def authenticate(request:, scopes:)
    permissions = request.headers["X-Scopes"].to_s.split(",")
    return nil unless scopes.all? { |scope| permissions.include?(scope) }

    Demo::User.new(id: 1, permissions: permissions)
  end
end

# Or keep the declared type, when it returns more than one variant.
class DemoApiKeyAuthenticator
  extend T::Sig
  include Server::Security::ApiKeyAuth

  sig do
    override.params(request: ActionDispatch::Request, scopes: T::Array[String])
            .returns(T.nilable(Demo::Principal))
  end
  def authenticate(request:, scopes:)
    key = request.headers[Server::Security::API_KEY_AUTH.parameter_name]
    return nil if key.nil?

    key == "root" ? Demo::User.new(id: 0, permissions: ["*"]) : Demo::Service.new(name: key)
  end
end
