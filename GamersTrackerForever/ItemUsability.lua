GamersTrackerForever = GamersTrackerForever or {}

-- A conservative, class-based equipment hint for saved characters.  WoW's
-- IsUsableItem answers whether the *logged-in* player can currently use an
-- item, so it cannot adjudicate an offline character or a future level.
local GTF = GamersTrackerForever
local ItemUsability = {}
GTF.ItemUsability = ItemUsability

local classByToken = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
  SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- Classic's permanent armor ceilings; the level-40 upgrades are not treated
-- as permanent incompatibilities.  The tooltip remains authoritative for
-- individual class/race/level/skill requirements.
local armorCeiling = {
  [1] = 4, [2] = 4, [3] = 3, [4] = 2, [5] = 1,
  [7] = 3, [8] = 1, [9] = 1, [11] = 2,
}

-- Classic Priest weapon subclasses: one-handed mace, staff, dagger, wand.
-- Fishing poles and unknown/custom subclasses intentionally stay undecided.
local knownWeapons = {
  [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
  [5] = true, [6] = true, [7] = true, [8] = true, [10] = true,
  [13] = true, [15] = true, [18] = true, [19] = true,
}
local priestWeapons = { [4] = true, [10] = true, [15] = true, [19] = true }

local function positive(value)
  value = tonumber(value)
  return value and value > 0 and value or nil
end

local function classID(character, env)
  if type(character) ~= "table" then return nil end
  local identity = type(character.identity) == "table" and character.identity or character
  local id = positive(character.classID) or positive(identity.classID)
  if id then return id end

  -- Older Forever snapshots can have classID=0.  Only borrow UnitClass for
  -- the very same player GUID; never apply the logged-in class to an alt.
  local guid = identity.guid or character.guid
  if type(guid) == "string" and guid ~= "" and type(env.UnitGUID) == "function"
    and type(env.UnitClass) == "function" then
    local okGUID, currentGUID = pcall(env.UnitGUID, "player")
    if okGUID and currentGUID == guid then
      local okClass, localized, token, numeric = pcall(env.UnitClass, "player")
      if okClass then
        return positive(numeric) or classByToken[tostring(token or localized or ""):upper()]
      end
    end
  end
  return classByToken[tostring(identity.classToken or identity.className or ""):upper()]
end

local function itemType(env, itemID)
  local instant = env.GetItemInfoInstant
    or (type(env.C_Item) == "table" and env.C_Item.GetItemInfoInstant)
  if type(instant) == "function" then
    local ok, id, _, _, equipLoc, _, itemClass, subclass = pcall(instant, itemID)
    if ok and positive(id) and itemClass ~= nil and subclass ~= nil and equipLoc ~= nil then
      return itemClass, subclass, equipLoc
    end
  end
  local info = env.GetItemInfo
    or (type(env.C_Item) == "table" and env.C_Item.GetItemInfo)
  if type(info) == "function" then
    local ok, name, _, _, _, _, _, _, _, equipLoc, _, _, itemClass, subclass = pcall(info, itemID)
    if ok and name then return itemClass, subclass, equipLoc end
  end
  return nil, nil, nil
end

-- Returns "unwearable" only for a confirmed, permanent Classic class/type
-- mismatch.  "no_known_restriction" does not promise the item can be equipped:
-- item-specific class, race, skill, and level conditions are outside this API.
function ItemUsability.GetStatus(env, itemID, character)
  env = type(env) == "table" and env or _G
  itemID = positive(itemID)
  if not itemID then return "unknown", "output item unavailable" end
  local itemClass, subclass, equipLoc = itemType(env, itemID)
  if itemClass == nil or subclass == nil or equipLoc == nil then
    return "unknown", "item type not cached"
  end
  if equipLoc == "" then return "not_equipment", "not wearable equipment" end
  itemClass, subclass = tonumber(itemClass), tonumber(subclass)
  if not itemClass or not subclass then return "unknown", "item type unavailable" end
  local klass = classID(character, env)
  if not klass then return "unknown", "character class unavailable" end

  if itemClass == 4 then -- Enum.ItemClass.Armor
    local ceiling = armorCeiling[klass]
    if not ceiling then return "unknown", "class rules unavailable" end
    if subclass >= 1 and subclass <= 4 then
      if subclass > ceiling then return "unwearable", "armor type unavailable to this class" end
      return "no_known_restriction", "armor type allowed; other requirements unverified"
    end
    if subclass == 6 and klass == 5 then
      return "unwearable", "Priests cannot equip shields"
    end
    return "unknown", "special armor rules unverified"
  end

  if itemClass == 2 and klass == 5 then -- Enum.ItemClass.Weapon
    if priestWeapons[subclass] then
      return "no_known_restriction", "weapon type allowed; skill and other requirements unverified"
    end
    if knownWeapons[subclass] then
      return "unwearable", "weapon type unavailable to Priests"
    end
    return "unknown", "custom or special weapon type"
  end
  return "unknown", "class/item restrictions unverified"
end

-- Viewer-mode convenience for UI that judges recipes against the logged-in
-- character rather than the saved crafter currently selected in the tree.
function ItemUsability.GetStatusForCurrentPlayer(env, itemID)
  env = type(env) == "table" and env or _G
  if type(env.UnitClass) ~= "function" then return "unknown", "player class unavailable" end
  local ok, localized, token, numeric = pcall(env.UnitClass, "player")
  if not ok then return "unknown", "player class unavailable" end
  local id = positive(numeric) or classByToken[tostring(token or localized or ""):upper()]
  return ItemUsability.GetStatus(env, itemID, { classID = id })
end
