# frozen_string_literal: true

Dummy::Application.routes.draw do
  scope "/v1" do
    Dummy::V1::Routes.draw(self)
  end
end
