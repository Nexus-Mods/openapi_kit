# typed: strict
# frozen_string_literal: true

require "optparse"

module Oapi
  module Codegen
    class Cli
      extend T::Sig

      sig { params(argv: T::Array[String], out: T.any(IO, StringIO), err: T.any(IO, StringIO)).returns(Integer) }
      def self.run(argv, out: $stdout, err: $stderr)
        new(out: out, err: err).run(argv)
      end

      private_class_method :new

      sig { params(out: T.any(IO, StringIO), err: T.any(IO, StringIO)).void }
      def initialize(out:, err:)
        @out = out
        @err = err
      end

      sig { params(argv: T::Array[String]).returns(Integer) }
      def run(argv)
        path = T.let("oapi.yml", String)

        parser = OptionParser.new do |options|
          options.banner = "Usage: oapi generate [-c CONFIG]"
          options.on("-c", "--config PATH", "Path to oapi.yml (default: oapi.yml)") { |value| path = value }
          options.on("-v", "--version", "Print the version") do
            @out.puts(VERSION)
            return 0
          end
          options.on("-h", "--help", "Print this message") do
            @out.puts(options)
            return 0
          end
        end

        rest = parser.parse(argv)
        command = rest.first || "generate"

        unless command == "generate"
          @err.puts("Unknown command #{command.inspect}.")
          @err.puts(parser)
          return 1
        end

        generate(path)
      rescue OptionParser::ParseError => e
        @err.puts(e.message)
        1
      end

      private

      sig { params(path: String).returns(Integer) }
      def generate(path)
        config = Config.from_file(path)
        generator = Generator.new(config: config)
        written = generator.generate

        generator.warnings.each { |warning| @err.puts("warning: #{warning}\n\n") }
        written.each { |file| @out.puts(file.relative_path_from(Pathname.pwd)) }
        0
      rescue ConfigError, SchemaError, Error => e
        @err.puts(e.message)
        1
      end
    end
  end
end
