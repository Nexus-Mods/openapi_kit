# typed: strict
# frozen_string_literal: true

# Generated controllers read the registry from Server::Registry.instance, so a base class
# owes them nothing but whatever the application wants to share.
class ApiBaseController < ActionController::API
end
