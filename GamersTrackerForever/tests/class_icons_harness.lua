GamersTrackerForever = {}
assert(loadfile("ClassIcons.lua"))()
local icons = GamersTrackerForever.ClassIcons

local path, left, right, top, bottom, token = icons.Resolve(5, "Mage")
assert(path == "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
assert(token == "PRIEST", "numeric class ID must win over localized or stale class name")
assert(left == 0.49609375 and right == 0.7421875 and top == 0.25 and bottom == 0.5)
assert(select(6, icons.Resolve(8, "")) == "MAGE")
assert(select(6, icons.Resolve(0, "Death Knight")) == "DEATHKNIGHT")
assert(icons.Resolve(99, "Unknown") == nil, "unknown classes must not show a wrong icon")

local texture = {
  SetTexture = function(self, value) self.path = value end,
  SetTexCoord = function(self, ...) self.coords = { ... } end,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
}
assert(icons.Apply(texture, 8, "Mage") and texture.shown)
assert(texture.path == path and texture.coords[1] == 0.25)
assert(not icons.Apply(texture, 99, "Unknown") and not texture.shown)
print("class_icons_harness: PASS")
