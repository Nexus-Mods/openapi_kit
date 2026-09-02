# typed: strong

module Openapi3Parser
  sig { params(path: T.any(String, Pathname)).returns(T.untyped) }
  def self.load_file(path); end

  sig { params(input: T.untyped).returns(T.untyped) }
  def self.load(input); end
end
