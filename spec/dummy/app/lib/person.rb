# frozen_string_literal: true

# What a successful bearerAuth authentication produces. The application owns this type;
# oapi writes it into the authenticator interface and the request context.
class Person < T::Struct
  const :id, Integer
  const :scopes, T::Array[String], default: []
end
