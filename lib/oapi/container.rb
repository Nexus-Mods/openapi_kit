# typed: strict
# frozen_string_literal: true

module Oapi
  module Container
    extend T::Sig

    sig { params(container: T.untyped, handlers: T::Hash[String, T::Module[T.anything]]).void }
    def self.verify!(container, handlers)
      problems = T.let([], T::Array[String])

      handlers.each do |key, interface|
        unless registered?(container, key)
          problems << "#{key} is not registered"
          next
        end

        handler = container.resolve(key)
        next if handler.is_a?(interface)

        problems << "#{key} resolves to #{handler.class}, which does not include #{interface}"
      end

      raise ContainerError, problems unless problems.empty?
    end

    # An error raised while building a handler is that handler's bug, not a missing
    # registration, so only the container's own lookup is treated as an answer.
    sig { params(container: T.untyped, key: String).returns(T::Boolean) }
    def self.registered?(container, key)
      return !!container.key?(key) if container.respond_to?(:key?)

      container.resolve(key)
      true
    rescue StandardError
      false
    end
  end
end
