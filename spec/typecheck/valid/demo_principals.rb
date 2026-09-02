# typed: strict
# frozen_string_literal: true

# The classes the server fixture's `principals` name. An application owns these; oapi
# only writes them into the authenticator interfaces and the request context.
module Demo
  class User < T::Struct
    const :id, Integer
  end

  class Service < T::Struct
    const :name, String
  end
end
