# typed: strict
# frozen_string_literal: true

require "yaml"
require "pathname"

module Oapi
  module Codegen
    class Config < T::Struct
      extend T::Sig

      const :spec, Pathname
      const :output, Pathname
      const :modules, T::Array[String]
      const :container_prefix, T.nilable(String), default: nil
      const :controller_base, String
      const :type_mappings, T::Hash[String, RubyType], default: {}
      const :name_overrides, T::Hash[String, String], default: {}

      KNOWN_KEYS = T.let(
        %w[
          spec output modules controller_base container_prefix
          type_mappings name_overrides
        ].freeze,
        T::Array[String]
      )

      sig { params(path: T.any(String, Pathname)).returns(Config) }
      def self.from_file(path)
        file = Pathname.new(path).expand_path
        raise ConfigError, "No such config file: #{file}" unless file.file?

        raw = YAML.safe_load(file.read, permitted_classes: [], aliases: true) || {}
        raise ConfigError, "#{file}: expected a YAML mapping, got #{raw.class}" unless raw.is_a?(Hash)

        from_hash(raw, base: file.dirname, source: file)
      end

      sig do
        params(raw: T::Hash[String, T.untyped], base: Pathname, source: T.nilable(Pathname))
          .returns(Config)
      end
      def self.from_hash(raw, base:, source: nil)
        where = source ? "#{source}: " : ""

        unknown = raw.keys.map(&:to_s) - KNOWN_KEYS
        unless unknown.empty?
          raise ConfigError,
                "#{where}unknown option#{"s" if unknown.size > 1} #{unknown.sort.join(", ")}. " \
                "Known options: #{KNOWN_KEYS.join(", ")}."
        end

        %w[spec output modules controller_base].each do |key|
          raise ConfigError, "#{where}`#{key}` is required." unless raw[key]
        end

        modules = Array(raw["modules"]).map(&:to_s)
        raise ConfigError, "#{where}`modules` must name at least one namespace, e.g. [API, V3]." if modules.empty?

        new(
          spec: base.join(raw.fetch("spec").to_s).expand_path,
          output: base.join(raw.fetch("output").to_s).expand_path,
          modules: modules,
          container_prefix: raw["container_prefix"]&.to_s,
          controller_base: raw.fetch("controller_base").to_s,
          type_mappings: parse_type_mappings(raw["type_mappings"]),
          name_overrides: stringify(raw["name_overrides"])
        )
      end

      sig { params(value: T.untyped).returns(T::Hash[String, RubyType]) }
      def self.parse_type_mappings(value)
        (value || {}).to_h do |key, mapping|
          [key.to_s, RubyType.parse("type_mappings[#{key.to_s.inspect}]", mapping)]
        end
      end

      sig { params(value: T.untyped).returns(T::Hash[String, String]) }
      def self.stringify(value)
        (value || {}).to_h { |k, v| [k.to_s, v.to_s] }
      end

      sig { returns(String) }
      def namespace = modules.join("::")

      sig { returns(String) }
      def module_path = modules.map { |name| Naming.snake(name) }.join("/")

      sig { params(parts: String).returns(String) }
      def container_key(*parts)
        [container_prefix, *parts].compact.join(".")
      end
    end
  end
end
