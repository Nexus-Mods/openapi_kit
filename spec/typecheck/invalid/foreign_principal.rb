# typed: strict
# frozen_string_literal: true

# An authenticator may narrow to a variant of the configured principal, but not step
# outside it: the request context would then carry a type no handler expects.
class ForeignPrincipalAuthenticator
  extend T::Sig
  include Server::Security::BearerAuth

  sig do
    override.params(request: ActionDispatch::Request, scopes: T::Array[String])
            .returns(T.nilable(String))
  end
  def authenticate(request:, scopes:) = "not a principal"
end
