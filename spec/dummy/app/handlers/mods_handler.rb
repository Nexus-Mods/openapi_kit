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
        Dummy::V1::Types::Mod.new(id: T.cast(request.principal, Principal::Token).user_id,
                                  name: "#{request.path.game_domain}:#{request.query.page}",
                                  status: Dummy::V1::Types::ModStatus::Live)
      ]
    )
  end

  # The operation offers bearerAuth or apiKeyAuth, and Principal is sealed, so this case
  # is exhaustive: adding a variant stops compiling here until it is handled.
  def create_mod(request:)
    author = case request.principal
             when Principal::Token then "user-#{request.principal.user_id}"
             when Principal::Key then request.principal.client
             else T.absurd(request.principal)
             end

    Dummy::V1::Operations::CreateMod::Created.new(
      body: Dummy::V1::Types::Mod.new(id: 2, name: "#{request.body.name} by #{author}", status: nil)
    )
  end
end
