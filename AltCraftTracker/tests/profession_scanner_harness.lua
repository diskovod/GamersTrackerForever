-- Lua 5.1 fixture tests for Task 4 profession/rank and learned-recipe scans.

local files = {
  "Constants.lua", "ApiCompat.lua", "ApiCompatProfessions.lua", "Repository.lua", "ProfessionScanner.lua",
}
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local rows = {
  { name = "Copper Bar", kind = "optimal", recipe = "|cff00ff00|Htrade:1001:0:0:0|h[Copper Bar]|h|r", item = "|cff1eff00|Hitem:2001:0:0:0|h[Copper Bar]|h|r", reagents = { { item = "|Hitem:3001:0:0:0|h[Copper Ore]|h", quantity = 1 } } },
  { name = "Silver Bar", kind = "optimal", recipe = "|Henchant:1002:0:0:0|h[Silver Bar]|h", item = "|Hitem:2002:0:0:0|h[Silver Bar]|h", reagents = { { item = "|Hitem:3002:0:0:0|h[Silver Ore]|h", quantity = 2 } } },
}
local professionActive = true
local enumerationFails = false
local scheduledCallback
local fixture = {
  WOW_PROJECT_ID = 2,
  WOW_PROJECT_CLASSIC_ERA = 2,
  GetBuildInfo = function() return "1.15.9", "63830", "test", 11509 end,
  UnitFullName = function() return "Ana", "Test Realm" end,
  UnitGUID = function() return "Player-1-0001" end,
  UnitClass = function() return "Warrior", 1 end,
  UnitFactionGroup = function() return "Alliance" end,
  UnitLevel = function() return 42 end,
  GetRealmName = function() return "Test Realm" end,
  GetProfessions = function()
    if enumerationFails then error("skill lines not settled") end
    if not professionActive then return nil end
    -- Later secondary slot populated while primary slots are empty.
    return nil, nil, 1
  end,
  -- Realistic Classic shape: numAbilities, spellOffset, skillLine, spec index.
  GetProfessionInfo = function() return "Blacksmithing", 123, 225, 300, 2, 9999, 164, 42 end,
  GetTradeSkillLine = function() return "Blacksmithing", 225, 300, 2, 9999, 164, 42 end,
  GetNumTradeSkills = function() return #rows end,
  GetTradeSkillInfo = function(index)
    local row = rows[index]
    return row.name, row.kind, 0, true
  end,
  GetTradeSkillRecipeLink = function(index) return rows[index].recipe end,
  GetTradeSkillItemLink = function(index) return rows[index].item end,
  GetTradeSkillNumMade = function(index) return index == 1 and 1 or 2, index == 1 and 1 or 3 end,
  GetTradeSkillNumReagents = function(index) return #rows[index].reagents end,
  GetTradeSkillReagentInfo = function(index, reagent) return "reagent", nil, rows[index].reagents[reagent].quantity, 0 end,
  GetTradeSkillReagentItemLink = function(index, reagent) return rows[index].reagents[reagent].item end,
}

local api = AltCraftTracker.ApiCompat.CreateClassic(fixture)
local repo = AltCraftTracker.Repository:Create({})
repo:Initialize(nil, api)
local scanner = AltCraftTracker.ProfessionScanner:Create(fixture, api, repo, {
  now = function() return 1000 end,
  schedule = function(_, callback) scheduledCallback = callback end,
})
scanner:Initialize()

local skills = scanner:RefreshRanks()
assert(skills.success and skills.professions["profession:164"].rank == 225)
assert(skills.professions["profession:164"].professionID == 164)
assert(skills.professions["profession:164"].specializationID == nil)
local result = scanner:ScanLoadedProfession()
assert(result.success and result.complete and result.learnedRecipes["recipe:1001"])
local product = repo:GetProduct("classic_era", true)
local character = repo:GetCharacter("classic_era", "Player-1-0001", false)
assert(product.recipes["recipe:1001"].outputItemID == 2001)
assert(product.recipes["recipe:1001"].reagents[1].itemID == 3001)
assert(character.professions["profession:164"].learnedRecipes["recipe:1002"])
assert(character.professions["profession:164"].scanState == "current")

-- A row with no usable link makes the scan incomplete and must preserve both
-- the previous learned set and product recipe definitions.
local oldRecipe = product.recipes["recipe:1001"]
local oldLearned = character.professions["profession:164"].learnedRecipes["recipe:1001"]
rows[1].recipe, rows[1].item = nil, nil
local failed = scanner:ScanLoadedProfession(1001)
assert(not failed.success and failed.complete == false)
assert(product.recipes["recipe:1001"] == oldRecipe)
assert(character.professions["profession:164"].learnedRecipes["recipe:1001"] == oldLearned)
rows[1].recipe, rows[1].item = "|Htrade:1001:0:0:0|h[Copper Bar]|h", "|Hitem:2001:0:0:0|h[Copper Bar]|h"
rows[1].reagents[1].item = nil
local missingReagent = scanner:ScanLoadedProfession(1002)
assert(not missingReagent.success and product.recipes["recipe:1001"] == oldRecipe)
rows[1].reagents[1].item = "|Hitem:3001:0:0:0|h[Copper Ore]|h"

-- A successful complete enumeration reconciles an abandoned profession.
professionActive = false
local reconciled = scanner:RefreshRanks(1003)
assert(reconciled.success and next(character.professions) == nil)

-- SHOW/UPDATE are coalesced until the injected scheduler fires. CLOSE flushes
-- a still-pending scan while the trade-skill data remains available.
professionActive = true
assert(scanner:HandleEvent("TRADE_SKILL_SHOW").pending)
assert(scanner:HandleEvent("TRADE_SKILL_UPDATE").pending)
assert(type(scheduledCallback) == "function")
scheduledCallback()
assert(character.professions["profession:164"].scanState == "current")
assert(scanner:HandleEvent("TRADE_SKILL_SHOW").pending)
local closed = scanner:HandleEvent("TRADE_SKILL_CLOSE")
assert(closed.closed and closed.success)
enumerationFails = true
local failedEnumeration = scanner:RefreshRanks(1004)
assert(not failedEnumeration.success and character.professions["profession:164"] ~= nil)

-- Link parsing is independent of hyperlink colours and display text.
assert(api:ParseItemID("|cffabc123|Hitem:9988:1:2:3|h[odd text]|h|r") == 9988)
assert(api:ParseRecipeID("|Htrade:777:0:0:0|h[x]|h") == 777)
assert(api:ParseRecipeID("|Henchant:888:0:0:0|h[x]|h") == 888)

print("AltCraft Tracker Task 4 profession scanner harness: PASS")
