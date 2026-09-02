# typed: strict
# frozen_string_literal: true

module PartialRender
  extend T::Sig

  sig { params(response: Server::Operations::ListMods::Response).returns(::Integer) }
  def self.call(response)
    case response
    when Server::Operations::ListMods::Ok then response.status
    else T.absurd(response)
    end
  end
end
