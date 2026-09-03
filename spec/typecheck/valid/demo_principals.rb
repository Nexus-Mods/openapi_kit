# typed: strict
# frozen_string_literal: true

# What `principal` names. The application owns this, and seals it so a handler's case
# over the variants is exhaustive.
module Demo
  module Principal
    extend T::Helpers
    sealed!
  end

  class User < T::Struct
    include Principal
    const :id, Integer
    const :permissions, T::Array[String]
  end

  class Service < T::Struct
    include Principal
    const :name, String
  end
end
