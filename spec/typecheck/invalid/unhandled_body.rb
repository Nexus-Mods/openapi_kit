# typed: strict
# frozen_string_literal: true

module UnhandledBody
  extend T::Sig

  sig { params(result: OpenAPIKit::Response).returns(::String) }
  def self.call(result)
    case (body = result.to_body)
    when OpenAPIKit::Body::Empty then "empty"
    when OpenAPIKit::Body::Json then "json"
    else T.absurd(body)
    end
  end
end
