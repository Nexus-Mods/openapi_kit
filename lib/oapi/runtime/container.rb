# typed: strict
# frozen_string_literal: true

module Oapi
  module Container
    extend T::Sig

    sig { params(container: T.untyped, handlers: T::Hash[String, T::Module[T.anything]]).void }
    def self.verify!(container, handlers)
      problems = T.let([], T::Array[String])

      handlers.each do |key, interface|
        handler =
          begin
            container.resolve(key)
          rescue StandardError => e
            problems << "#{key} is not registered (#{e.class}: #{e.message})"
            next
          end

        next if handler.is_a?(interface)

        problems << "#{key} resolves to #{handler.class}, which does not include #{interface}"
      end

      raise ContainerError, problems unless problems.empty?
    end
  end
end
