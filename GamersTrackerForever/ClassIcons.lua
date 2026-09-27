local GTF = GamersTrackerForever
local ClassIcons = {}
GTF.ClassIcons = ClassIcons

ClassIcons.TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- The classic character-creation sprite uses the same coordinates as
-- Blizzard's CLASS_ICON_TCOORDS. Keep a local copy because that global is not
-- guaranteed to be loaded in every client or UI state.
local coordinates = {
  WARRIOR = { 0, 0.25, 0, 0.25 },
  MAGE = { 0.25, 0.49609375, 0, 0.25 },
  ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
  HUNTER = { 0, 0.25, 0.25, 0.5 },
  SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
  WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },
  DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 },
}

local tokenByID = {
  [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER",
  [4] = "ROGUE", [5] = "PRIEST", [6] = "DEATHKNIGHT",
  [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}

function ClassIcons.Resolve(classID, className)
  local token = tokenByID[tonumber(classID)]
  if not token and type(className) == "string" then
    local candidate = className:upper():gsub("[%s%-]", "")
    if coordinates[candidate] then token = candidate end
  end
  local coords = token and coordinates[token]
  if not coords then return nil end
  return ClassIcons.TEXTURE, coords[1], coords[2], coords[3], coords[4], token
end

function ClassIcons.Apply(texture, classID, className)
  if not texture then return false end
  local path, left, right, top, bottom = ClassIcons.Resolve(classID, className)
  if not path then
    if type(texture.Hide) == "function" then texture:Hide() end
    return false
  end
  texture:SetTexture(path)
  texture:SetTexCoord(left, right, top, bottom)
  if type(texture.Show) == "function" then texture:Show() end
  return true
end
