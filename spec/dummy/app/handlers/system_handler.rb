# frozen_string_literal: true

class SystemHandler
  include Dummy::V1::Handlers::System

  def get_health(request:) = Dummy::V1::Operations::GetHealth::Ok.new
end
