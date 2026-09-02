# typed: strict
# frozen_string_literal: true

class ModsHandler
  extend T::Sig
  include Server::Handlers::Mods

  sig do
    override
      .params(request: Server::Operations::ListMods::Request)
      .returns(Server::Operations::ListMods::Response)
  end
  def list_mods(request:)
    return Server::Operations::ListMods::BadRequest.new(
      body: Server::Types::ProblemDetails.new(title: "bad page")
    ) if request.query.page < 1

    Server::Operations::ListMods::Ok.new(body: [])
  end

  sig do
    override
      .params(request: Server::Operations::CreateMod::Request)
      .returns(Server::Operations::CreateMod::Response)
  end
  def create_mod(request:)
    Server::Operations::CreateMod::Created.new(
      body: Server::Types::Mod.new(id: 1, name: request.body.name)
    )
  end
end

module Render
  extend T::Sig

  sig { params(response: Server::Operations::ListMods::Response).returns([::Integer, ::Oapi::Wire::Out]) }
  def self.call(response)
    case response
    when Server::Operations::ListMods::Ok then [response.status, response.to_wire]
    when Server::Operations::ListMods::BadRequest then [response.status, response.to_wire]
    else T.absurd(response)
    end
  end
end
