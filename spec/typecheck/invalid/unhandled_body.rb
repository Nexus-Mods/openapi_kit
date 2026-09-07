# typed: strict
# frozen_string_literal: true

module UnhandledBody
  extend T::Sig

  sig { params(result: Oapi::Response).returns(::String) }
  def self.call(result)
    case (body = result.to_body)
    when Oapi::Body::Empty then "empty"
    when Oapi::Body::Json then "json"
    else T.absurd(body)
    end
  end
end
