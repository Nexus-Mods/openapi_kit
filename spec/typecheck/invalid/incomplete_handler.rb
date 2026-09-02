# typed: strict
# frozen_string_literal: true

class PartialModsHandler
  extend T::Sig
  include Server::Handlers::Mods

  sig do
    override
      .params(request: Server::Operations::ListMods::Request)
      .returns(Server::Operations::ListMods::Response)
  end
  def list_mods(request:) = Server::Operations::ListMods::Ok.new(body: [])
end
