# frozen_string_literal: true

class ModsHandler
  include Dummy::V1::Handlers::Mods

  def list_mods(request:)
    if request.query.page < 1
      return Dummy::V1::Operations::ListMods::BadRequest.new(
        body: Dummy::V1::Types::ProblemDetails.new(title: "bad page")
      )
    end

    Dummy::V1::Operations::ListMods::Ok.new(
      body: [
        Dummy::V1::Types::Mod.new(id: 1, name: "#{request.path.game_domain}:#{request.query.page}",
                                  status: Dummy::V1::Types::ModStatus::Live)
      ]
    )
  end

  def create_mod(request:)
    Dummy::V1::Operations::CreateMod::Created.new(
      body: Dummy::V1::Types::Mod.new(id: 2, name: request.body.name, status: nil)
    )
  end
end
