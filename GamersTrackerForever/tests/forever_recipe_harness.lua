-- Complete Forever beta scan, duplicate IDs, and fail-closed preservation.
for _, file in ipairs({ "Constants.lua", "Repository.lua", "ProfessionScanner.lua", "ForeverRecipeScanner.lua" }) do
  assert(loadfile(file))()
end

local GTF = GamersTrackerForever
GTF.Now = function() return 1000 end
local callback, list = nil, { 1001, 1002, 1003, 1001 }
local ambiguous, mixed, malformed = false, false, false
local env = {
  C_Timer = { After = function(_, fn) callback = fn end },
  C_TradeSkillUI = {
    GetAllRecipeIDs = function() return malformed and { 1001, "bad" } or list end,
    GetRecipeInfo = function(id)
      return { recipeID = id, name = "Recipe " .. id, learned = id ~= 1003,
        icon = 44, categoryID = id == 1001 and 22 or 23 }
    end,
    GetCategoryInfo = function(id)
      if id == 22 then return { name = "Mail Leggings", parentCategoryID = 21 } end
      if id == 21 then return { name = "Armor", parentCategoryID = 0 } end
      if id == 23 then return { name = "Weapon Stones", parentCategoryID = 0 } end
    end,
    GetProfessionInfoByRecipeID = function(id)
      if mixed and id == 1003 then return { professionID = 1234, professionName = "Cooking" } end
      return { professionID = 2938, professionName = "Blacksmithing" }
    end,
    GetRecipeSchematic = function(id, isRecraft)
      assert(isRecraft == false)
      return { outputItemID = id + 1000, quantityMin = 1, quantityMax = 2,
        reagentSlotSchematics = { { quantityRequired = 2, reagents = ambiguous
          and { { itemID = 118 }, { itemID = 2840 } } or { { itemID = 118, name = "Rough Stone", icon = 123 } } } } }
    end,
  },
}
local api = {
  GetCurrentContext = function() return { productKey = "forever_beta", characterKey = "Player-1-ABC" } end,
  GetProfessionEntries = function() return { { name = "Blacksmithing", rank = 53, maxRank = 75, professionID = 0 } } end,
  GetClientInfo = function() return { build = "70009" } end,
}
local repo = GTF.Repository:Create(env)
repo:Initialize(nil, api)
local rank = GTF.ProfessionScanner:Create(env, api, repo, { now = GTF.Now, rankOnly = true })
assert(rank:RefreshRanks().success)
local modern = GTF.ForeverRecipeScanner:Create(env, api, repo, rank)
modern:HandleEvent("TRADE_SKILL_SHOW")
assert(type(callback) == "function")
callback()
local product = repo:GetProduct("forever_beta", false)
local character = repo:GetCharacter("forever_beta", "Player-1-ABC", false)
local profession = character.professions["profession:blacksmithing"]
assert(profession.scanState == "current")
assert(profession.learnedRecipes["recipe:1001"] and profession.learnedRecipes["recipe:1002"])
assert(not profession.learnedRecipes["recipe:1003"])
assert(product.recipes["recipe:1001"].professionID == 2938)
assert(product.recipes["recipe:1001"].categoryID == 22)
assert(product.recipes["recipe:1001"].categoryName == "Mail Leggings")
assert(product.recipes["recipe:1001"].categoryPath[1] == "Armor")
assert(product.recipes["recipe:1001"].categoryPath[2] == "Mail Leggings")
assert(product.recipes["recipe:1002"].categoryName == "Weapon Stones")
assert(product.recipes["recipe:1001"].reagents[1].itemID == 118)
assert(product.recipes["recipe:1001"].reagents[1].quantity == 2)
assert(product.recipes["recipe:1001"].reagents[1].name == "Rough Stone", "schematic name survives persistence")
assert(product.recipes["recipe:1001"].outputMin == 1)
assert(product.recipes["recipe:1001"].outputMax == 2)

ambiguous = true
local failed = modern:ScanOpen(1100)
assert(not failed.success and failed.error:match("ambiguous"))
assert(profession.learnedRecipes["recipe:1002"], "failed scan must preserve learned set")
assert(product.recipes["recipe:1001"].reagents[1].itemID == 118,
  "failed scan must preserve recipe definitions")
ambiguous = false
mixed = true
assert(not modern:ScanOpen(1100).success, "mixed profession list must not commit")
mixed = false
malformed = true
assert(not modern:ScanOpen(1100).success, "invalid recipe ID must not commit")
malformed = false

-- Missing category metadata is not a recipe-data failure.
local categoryLookup = env.C_TradeSkillUI.GetCategoryInfo
env.C_TradeSkillUI.GetCategoryInfo = nil
assert(modern:ScanOpen(1150).success)
assert(product.recipes["recipe:1001"].categoryID == 22)
assert(product.recipes["recipe:1001"].categoryName == nil)
env.C_TradeSkillUI.GetCategoryInfo = categoryLookup

list = { 1001, 1003 }
assert(modern:ScanOpen(1200).success)
profession = repo:GetCharacter("forever_beta", "Player-1-ABC", false)
  .professions["profession:blacksmithing"]
assert(profession.learnedRecipes["recipe:1001"] and not profession.learnedRecipes["recipe:1002"],
  "complete scan reconciles learned set")
assert(product.recipes["recipe:1002"], "global recipe definition remains cached")
modern:HandleEvent("TRADE_SKILL_SHOW")
local cancelled = callback
modern:HandleEvent("TRADE_SKILL_CLOSE")
cancelled()
assert(not modern.pending and not modern.scheduled)
print("forever_recipe_harness: ok")
