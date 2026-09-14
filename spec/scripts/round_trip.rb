# frozen_string_literal: true

require "openapi_kit"
require "zeitwerk"

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path(ARGV.fetch(0)))
loader.setup
loader.eager_load

WIRE = {
  "id" => 7,
  "name" => "Cool Mod",
  "status" => "under-moderation",
  "updatedAt" => "2026-09-02T10:00:00Z",
  "deletedAt" => nil,
  "bio" => nil,
  "owner" => { "id" => "0f3a2b1c-1111-2222-3333-444455556666", "name" => "jack" },
  "tags" => %w[a b],
  "meta" => { "note" => "hi" },
  "extra" => { "downloads" => 12 }
}.freeze

def check(label)
  raise "failed: #{label}" unless yield
end

mod = KitchenSink::Types::Mod::Codec.from_wire(WIRE)

check("id") { mod.id == 7 }
check("inline enum hoisted") { mod.status == KitchenSink::Types::ModStatus::UnderModeration }
check("date-time") { mod.updated_at == Time.utc(2026, 9, 2, 10) }
check("required nullable") { mod.deleted_at.nil? }
check("absent optional") { mod.summary.nil? }
check("default applied") { mod.page_size == 20 }
check("tristate present nil") { mod.bio == OpenAPIKit::Present.new(nil) }
check("tristate present value") { mod.owner.value_or(nil)&.name == "jack" }
check("alias inlined to String") { mod.owner.value_or(nil)&.id.is_a?(String) }
check("array items") { mod.tags == %w[a b] }
check("inline object hoisted") { mod.meta&.note == "hi" }
check("additionalProperties") { mod.extra == { "downloads" => 12 } }
other = KitchenSink::Types::Mod::Codec.from_wire(WIRE)
check("equality") { other == mod }
check("eql? agrees with ==") { other.eql?(mod) }
check("hash agrees with ==") { other.hash == mod.hash }
check("usable as a hash key") { { mod => :found }[other] == :found }
check("uniq collapses equal values") { [mod, other].uniq.size == 1 }
check("differing values are unequal") { KitchenSink::Types::Mod::Codec.from_wire(WIRE.merge("id" => 8)) != mod }

wire = KitchenSink::Types::Mod::Codec.to_wire(mod)
check("dumped date-time") { wire["updatedAt"] == "2026-09-02T10:00:00.000Z" }
check("dumped enum") { wire["status"] == "under-moderation" }
check("required nullable stays null") { wire.key?("deletedAt") && wire["deletedAt"].nil? }
check("absent optional omitted") { !wire.key?("summary") }
check("tristate null kept") { wire.key?("bio") && wire["bio"].nil? }

cat = KitchenSink::Types::Pet::Codec.from_wire({ "kind" => "cat", "lives" => 9 })
check("discriminated union") { cat.is_a?(KitchenSink::Types::Cat) }
check("union dump") { KitchenSink::Types::Pet::Codec.to_wire(cat)["kind"] == "cat" }

check("untagged union string") { KitchenSink::Types::Loose::Codec.from_wire("x") == "x" }
check("untagged union integer") { KitchenSink::Types::Loose::Codec.from_wire(3) == 3 }

begin
  KitchenSink::Types::Mod::Codec.from_wire(WIRE.merge("id" => "not a number"))
  raise "failed: expected a DecodeError"
rescue OpenAPIKit::DecodeError => e
  check("error names the field") { e.json_pointer == "/id" }
end

begin
  KitchenSink::Types::Mod::Codec.from_wire(WIRE.merge("tags" => ["a", 2]))
  raise "failed: expected a DecodeError"
rescue OpenAPIKit::DecodeError => e
  check("error indexes the element: #{e.json_pointer}") { e.json_pointer == "/tags/1" }
end

puts "round trip ok"
