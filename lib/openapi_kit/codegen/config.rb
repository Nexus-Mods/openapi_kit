# typed: strict
# frozen_string_literal: true

require "yaml"
require "pathname"

module OpenAPIKit
  module Codegen
    class Config < T::Struct
      extend T::Sig

      const :spec, Pathname
      const :output, Pathname
      const :modules, T::Array[String]
      const :controller_base, String
      const :type_mappings, T::Hash[String, RubyType], default: {}
      const :name_overrides, T::Hash[String, String], default: {}
      const :principal, T.nilable(String), default: nil

      KNOWN_KEYS = T.let(
        %w[
          spec output modules controller_base
          type_mappings name_overrides principal
        ].freeze,
        T::Array[String]
      )

      sig { params(path: T.any(String, Pathname)).returns(Config) }
      def self.from_file(path)
        file = Pathname.new(path).expand_path
        raise ConfigError, "No such config file: #{file}" unless file.file?

        from_yaml(file.read, relative_to: file)
      end

      sig { params(yaml: String, relative_to: Pathname).returns(Config) }
      def self.from_yaml(yaml, relative_to:)
        raw = YAML.safe_load(yaml, permitted_classes: [], aliases: true) || {}
        raise ConfigError, "#{relative_to}: expected a YAML mapping, got #{raw.class}" unless raw.is_a?(Hash)

        reject_unknown_options!(raw, relative_to)
        reject_missing_options!(raw, relative_to)
        base = relative_to.dirname

        new(
          spec: base.join(raw.fetch("spec").to_s).expand_path,
          output: base.join(raw.fetch("output").to_s).expand_path,
          modules: modules_in(raw, relative_to),
          controller_base: raw.fetch("controller_base").to_s,
          type_mappings: parse_type_mappings(raw["type_mappings"]),
          name_overrides: stringify(raw["name_overrides"]),
          principal: principal_type(raw["principal"], "#{relative_to}: ")
        )
      end

      sig { params(raw: T::Hash[String, T.untyped], file: Pathname).void }
      def self.reject_unknown_options!(raw, file)
        unknown = raw.keys.map(&:to_s) - KNOWN_KEYS
        return if unknown.empty?

        raise ConfigError,
              "#{file}: unknown option#{"s" if unknown.size > 1} #{unknown.sort.join(", ")}. " \
              "Known options: #{KNOWN_KEYS.join(", ")}."
      end

      sig { params(raw: T::Hash[String, T.untyped], file: Pathname).void }
      def self.reject_missing_options!(raw, file)
        %w[spec output modules controller_base].each do |key|
          raise ConfigError, "#{file}: `#{key}` is required." unless raw[key]
        end
      end

      sig { params(raw: T::Hash[String, T.untyped], file: Pathname).returns(T::Array[String]) }
      def self.modules_in(raw, file)
        modules = Array(raw["modules"]).map(&:to_s)
        return modules unless modules.empty?

        raise ConfigError, "#{file}: `modules` must name at least one namespace, e.g. [API, V3]."
      end

      sig { params(value: T.untyped).returns(T::Hash[String, RubyType]) }
      def self.parse_type_mappings(value)
        (value || {}).to_h do |key, mapping|
          [key.to_s, RubyType.parse("type_mappings[#{key.to_s.inspect}]", mapping)]
        end
      end

      # Authenticating produces a principal of a type only the application knows, so it
      # names it here and every authenticator interface returns it.
      sig { params(value: T.untyped, where: String).returns(T.nilable(String)) }
      def self.principal_type(value, where)
        return nil if value.nil?

        type = value.to_s
        return type if type.match?(RubyType::CONSTANT_PATH)

        raise ConfigError,
              "#{where}`principal` is #{type.inspect}, which is not a Ruby constant path. It " \
              "must name the class a successful authentication produces, e.g. \"MyApp::Principal\"."
      end

      sig { params(value: T.untyped).returns(T::Hash[String, String]) }
      def self.stringify(value)
        (value || {}).to_h { |k, v| [k.to_s, v.to_s] }
      end

      # The namespace as a path, which is what Rails routing wants in `to:`. File paths
      # come from `output` instead, so this no longer decides where anything is written.
      sig { returns(String) }
      def module_path = modules.map { |name| Naming.snake(name) }.join("/")

      sig { returns(String) }
      def namespace = modules.join("::")
    end
  end
end
