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

local api = GamersTrackerForever.ApiCompat.CreateClassic(fixture)
local repo = GamersTrackerForever.Repository:Create({})
repo:Initialize(nil, api)
local scanner = GamersTrackerForever.ProfessionScanner:Create(fixture, api, repo, {
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

-- Enchanting uses the Classic Craft window: recipe identity comes from the
-- enchant link, there is no output item, and reagents are keyed by item ID.
enumerationFails = false
fixture.GetProfessions = function() return nil, nil, 1, 2 end
fixture.GetProfessionInfo = function(index)
  if index == 2 then return "Enchanting", 136244, 150, 225, 40, 500, 333, 0 end
  return "Blacksmithing", 123, 225, 300, 2, 9999, 164, 42
end
local craftLine = "Enchanting"
local crafts = {
  { name = "Enchanting", craftType = "header", expanded = true },
  { name = "Enchant Bracer - Minor Health", craftType = "optimal", link = "|cffffffff|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r",
    reagents = { { item = "|Hitem:10940:0:0:0|h[Strange Dust]|h", quantity = 1 } } },
  { name = "Minor Wizard Oil", craftType = "medium", link = "|Hitem:20744:0:0:0|h[Minor Wizard Oil]|h",
    reagents = { { item = "|Hitem:10940:0:0:0|h[Strange Dust]|h", quantity = 2 }, { item = "|Hitem:17034:0:0:0|h[Maple Seed]|h", quantity = 1 } } },
}
fixture.GetCraftDisplaySkillLine = function() return craftLine, 150, 225 end
fixture.GetNumCrafts = function() return #crafts end
fixture.GetCraftInfo = function(index) local c = crafts[index]; return c.name, "", c.craftType, 0, c.expanded, 0, 0 end
fixture.GetCraftItemLink = function(index) return crafts[index].link end
fixture.GetCraftIcon = function() return 135913 end
fixture.GetCraftNumReagents = function(index) return #(crafts[index].reagents or {}) end
fixture.GetCraftReagentInfo = function(index, r) return "reagent", nil, crafts[index].reagents[r].quantity, 0 end
fixture.GetCraftReagentItemLink = function(index, r) return crafts[index].reagents[r].item end
assert(api:GetCapabilities().learned_recipe_scan)
scanner:RefreshRanks(1100)
assert(scanner:HandleEvent("CRAFT_SHOW").pending and api:GetTradeSource() == "craft")
local craftClosed = scanner:HandleEvent("CRAFT_CLOSE")
assert(craftClosed.closed and craftClosed.success, tostring(craftClosed.error))
local enchant = product.recipes["recipe:7418"]
assert(enchant and enchant.professionID == 333 and enchant.outputItemID == 0 and enchant.recipeID == 7418)
assert(enchant.reagents[1].itemID == 10940 and enchant.reagents[1].quantity == 1)
local oil = product.recipes["item:20744"]
assert(oil and oil.outputItemID == 20744 and #oil.reagents == 2)
local enchanting = character.professions["profession:333"]
assert(enchanting.learnedRecipes["recipe:7418"] and enchanting.learnedRecipes["item:20744"])
assert(enchanting.scanState == "current" and enchanting.rank == 150)

-- Beast Training shares the Craft window and must not become a profession.
craftLine = "Beast Training"
local beast = scanner:ScanLoadedProfession(1101)
assert(not beast.success and character.professions["profession:beasttraining"] == nil)

-- A pending craft scan is flushed against the Craft API before the trade
-- window takes over, and trade scanning still works afterwards.
craftLine = "Enchanting"
crafts[4] = { name = "Enchant Chest - Minor Mana", craftType = "easy", link = "|Henchant:7443|h[x]|h",
  reagents = { { item = "|Hitem:10938:0:0:0|h[Lesser Magic Essence]|h", quantity = 1 } } }
scanner:HandleEvent("CRAFT_UPDATE")
assert(scanner:HandleEvent("TRADE_SKILL_SHOW").pending and api:GetTradeSource() == "trade")
assert(character.professions["profession:333"].learnedRecipes["recipe:7443"])
local tradeAgain = scanner:HandleEvent("TRADE_SKILL_CLOSE")
assert(tradeAgain.success and tradeAgain.learnedRecipes["recipe:1001"])
assert(character.professions["profession:164"].learnedRecipes["recipe:1002"])

print("GamersTrackerForever Task 4 profession scanner harness: PASS")
