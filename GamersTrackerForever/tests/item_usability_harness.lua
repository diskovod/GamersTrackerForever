local chunk, err = loadfile("ItemUsability.lua")
assert(chunk, err)
chunk()

local usability = GamersTrackerForever.ItemUsability
local itemTypes = {
  [1] = { 4, 3, "INVTYPE_LEGS" }, -- mail legs
  [2] = { 4, 1, "INVTYPE_CHEST" }, -- cloth chest
  [3] = { 2, 10, "INVTYPE_2HWEAPON" }, -- staff
  [4] = { 2, 7, "INVTYPE_WEAPON" }, -- sword
  [5] = { 4, 4, "INVTYPE_HEAD" }, -- plate head
  [6] = { 7, 0, "" }, -- trade good
  [7] = { 4, 6, "INVTYPE_SHIELD" }, -- shield
  [8] = { 2, 42, "INVTYPE_WEAPON" }, -- unknown/custom weapon
}
local env = {
  GetItemInfoInstant = function(id)
    local item = itemTypes[id]
    if not item then return nil end
    return id, "", "", item[3], 0, item[1], item[2]
  end,
  UnitGUID = function() return "Player-current" end,
  UnitClass = function() return "Priest", "PRIEST", nil end,
}
local function status(id, character)
  return usability.GetStatus(env, id, character)
end
local function equals(actual, wanted, label)
  assert(actual == wanted, label .. ": expected " .. wanted .. ", got " .. tostring(actual))
end

local priest = { identity = { guid = "Player-current", classID = 5 } }
equals(status(1, priest), "unwearable", "priest versus mail")
equals(status(2, priest), "no_known_restriction", "priest versus cloth")
equals(status(3, priest), "no_known_restriction", "priest versus staff")
equals(status(4, priest), "unwearable", "priest versus sword")
equals(status(7, priest), "unwearable", "priest versus shield")
equals(status(8, priest), "unknown", "unknown weapon is not a red cross")
equals(status(6, priest), "not_equipment", "trade goods have no cross")
equals(status(99, priest), "unknown", "missing item data has no cross")
equals(status(5, { classID = 1 }), "no_known_restriction", "warrior plate is not permanently restricted")
equals(status(5, { classID = 3 }), "unwearable", "hunter plate")
equals(status(1, { identity = { classID = 0, guid = "Player-other" } }), "unknown", "do not borrow player's class for an alt")
equals(status(1, { identity = { classID = 0, guid = "Player-current" } }), "unwearable", "current GUID may use live class")
equals(usability.GetStatusForCurrentPlayer(env, 1), "unwearable", "current-player mode")
equals(usability.GetStatusForCurrentPlayer(env, 3), "no_known_restriction", "current-player allowed staff")
equals(usability.GetStatusForCurrentPlayer({}, 1), "unknown", "current-player class API absent")

local fallback = {
  GetItemInfo = function(id)
    if id ~= 1 then return nil end
    -- Official return fields: equipLoc=9, classID=12, subclassID=13.
    -- Sentinels at 10/14 catch a one-place shift in the pcall tuple.
    return "Mail Legs", nil, nil, nil, nil, nil, nil, nil,
      "INVTYPE_LEGS", "WRONG_SLOT", nil, 4, 3, 99
  end,
}
equals(usability.GetStatus(fallback, 1, priest), "unwearable", "cached GetItemInfo fallback")
equals(usability.GetStatus({}, 1, priest), "unknown", "missing APIs are safe")
local cItem = { C_Item = { GetItemInfoInstant = function(id)
  assert(type(id) == "number", "C_Item.GetItemInfoInstant takes an item ID, not a self table")
  return env.GetItemInfoInstant(id)
end } }
equals(usability.GetStatus(cItem, 1, priest), "unwearable", "C_Item modern namespace")
local cItemFallback = { C_Item = { GetItemInfo = fallback.GetItemInfo } }
equals(usability.GetStatus(cItemFallback, 1, priest), "unwearable", "C_Item cached fallback")
local incompleteInstant = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, nil, nil end,
  GetItemInfo = fallback.GetItemInfo }
equals(usability.GetStatus(incompleteInstant, 1, priest), "unwearable", "incomplete instant result falls back to cache")
local malformed = { GetItemInfoInstant = function() return 1, "", "", "INVTYPE_LEGS", 0, "bad", "bad" end }
equals(usability.GetStatus(malformed, 1, priest), "unknown", "malformed item type stays unknown")
local lowLevelPriest = { identity = { classID = 5 }, level = 1 }
equals(status(2, lowLevelPriest), "no_known_restriction", "level is not a permanent class restriction")

print("item_usability_harness: PASS")
