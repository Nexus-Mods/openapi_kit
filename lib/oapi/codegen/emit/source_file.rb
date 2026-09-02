# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class SourceFile < T::Struct
        const :path, String
        const :contents, String
      end

      module Source
        extend T::Sig

        sig do
          params(path: String, modules: T::Array[String], block: T.proc.params(buffer: Buffer).void)
            .returns(SourceFile)
        end
        def self.file(path:, modules:, &block)
          buffer = Buffer.new
          buffer.line("# typed: strict")
          buffer.line("# frozen_string_literal: true")
          buffer.blank
          buffer.nest_modules(modules) { block.call(buffer) }
          SourceFile.new(path: path, contents: buffer.to_s)
        end
      end
    end
  end
end
