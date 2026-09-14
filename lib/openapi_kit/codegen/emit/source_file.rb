# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class SourceFile < T::Struct
        const :path, String
        const :contents, String
        const :beside_output, T::Boolean, default: false
      end

      module Source
        extend T::Sig

        sig do
          params(path: String, modules: T::Array[String], beside_output: T::Boolean,
                 block: T.proc.params(buffer: Buffer).void).returns(SourceFile)
        end
        def self.file(path:, modules:, beside_output: false, &block)
          buffer = Buffer.new
          buffer.line("# typed: strict")
          buffer.line("# frozen_string_literal: true")
          buffer.blank
          buffer.nest_modules(modules) { block.call(buffer) }
          SourceFile.new(path: path, contents: buffer.to_s, beside_output: beside_output)
        end
      end
    end
  end
end
