-- Selected-recipe material labels never expose an item ID when item data is uncached.
assert(loadfile("ViewModels.lua"))()
local build = GamersTrackerForever.ViewModels.BuildMaterialRows
local calculation = { reagents = { { itemID = 2840, quantity = 10, kind = "item" } } }

local function label(source, resolver)
  local recipe = { reagents = { source or { itemID = 2840, quantity = 10 } } }
  local rows = build(recipe, calculation, { itemResolver = resolver })
  assert(rows[1].itemID == 2840, "ID remains available internally for item tooltip")
  return rows[1]
end

assert(label(nil, function() return "Copper Bar", nil, 123 end).name == "Copper Bar")
assert(label(nil, function() return nil, "|Hitem:2840:0|h[Copper Bar]|h", 123 end).name == "Copper Bar")
assert(label({ itemID = 2840, name = "Saved Copper Bar", icon = 456 }, function() return nil, nil, 123 end).name == "Saved Copper Bar")
assert(label({ itemID = 2840, link = "|Hitem:2840:0|h[Saved Copper Bar]|h" }).name == "Saved Copper Bar")
local unknown = label(nil, function() return nil, nil, 123 end)
assert(unknown.name == "Unknown material" and unknown.icon == 123)
assert(not unknown.name:find("2840", 1, true), "uncached item ID must not leak into material display")
assert(label(nil, function() return "Item 2840" end).name == "Unknown material")
assert(label({ itemID = 2840, name = "Copper Bar" }, function() return "Item 2840" end).name == "Copper Bar")
assert(label(nil, function() error("item cache unavailable") end).name == "Unknown material")
print("material_names_harness: PASS")
