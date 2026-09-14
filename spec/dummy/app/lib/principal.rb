# frozen_string_literal: true

# What `principal` names in openapi_kit.yml. The application owns it and seals it, so a handler
# casing over the variants is exhaustive. The variants are nested because sealed! needs
# them in one file, and Zeitwerk only asks that the file define Principal.
module Principal
  extend T::Helpers
  sealed!

  # A JWT carries its permissions.
  class Token < T::Struct
    include Principal
    const :user_id, Integer
    const :permissions, T::Array[String]
  end

  # An API key does not.
  class Key < T::Struct
    include Principal
    const :client, String
  end
end
