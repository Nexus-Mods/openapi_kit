# frozen_string_literal: true

# Stands in for the class an application names in `principal`. Sealed, so a handler
# casing over the variants is exhaustive.
module SpecPrincipal
  extend T::Helpers
  sealed!

  class Token < T::Struct
    include SpecPrincipal
    const :id, Integer
  end
end
