-- Lua 5.1 pure fixtures for Task 5 catalog and craftability contracts.

local files = { "Constants.lua", "Repository.lua", "CraftabilityService.lua", "RecipeCatalog.lua" }
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local function same(actual, expected, message)
  assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local repo = GamersTrackerForever.Repository:Create({})
local db = repo:Initialize(nil)
db.settings.staleAfterSeconds = 100
db.settings.veryStaleAfterSeconds = 500
local product = repo:GetProduct("classic_era", true)

local function character(key, name, group, tracked, bags, bank, bagsAt, bankAt)
  product.characters[key] = {
    tracked = tracked,
    identity = { displayName = name, transferGroup = group, faction = "Alliance" },
    professions = { alchemy = { professionID = 171, name = "Alchemy", learnedRecipes = {} } },
    inventory = {
      bags = bags or {}, bank = bank or {},
      bagsScannedAt = bagsAt or 0, bankScannedAt = bankAt or 0,
    },
  }
  return product.characters[key]
end

local ana = character("ana", "Ana", "realm|alliance", true, { [100] = 4, [200] = 7 }, {}, 1990, 0)
local corvin = character("corvin", "Corvin", "realm|alliance", true, { [100] = 3, [200] = 1 }, { [100] = 5, [200] = 10 }, 1999, 1800)
local isolated = character("isolated", "Isolated", "other-realm|alliance", true, { [100] = 100 }, {}, 1999, 1999)
local untracked = character("untracked", "Untracked", "realm|alliance", false, { [100] = 100 }, { [200] = 100 }, 1999, 1999)
local empty = character("empty", "Empty", "realm|alliance", true, {}, {}, 2000, 2000)
local priority = character("priority", "Priority", "priority", true, { [100] = 1 }, {}, 1800, 2000)
local unscannedBags = character("unscanned-bags", "Unscanned Bags", "unscanned", true, {}, { [100] = 99 }, 0, 2000)

local recipe = {
  recipeID = 500, professionID = 171, name = "Test Transmute", outputItemID = 900,
  reagents = { { itemID = 100, quantity = 10, kind = "item" } },
}
product.recipes["recipe:500"] = recipe
-- An output-ID fallback for the same product is deduplicated and does not
-- produce a second catalog row.
product.recipes["item:900"] = { recipeID = 500, professionID = 171, name = "Test Transmute", outputItemID = 900, reagents = recipe.reagents }
ana.professions.alchemy.learnedRecipes["recipe:500"] = true
corvin.professions.alchemy.learnedRecipes["item:900"] = true
isolated.professions.alchemy.learnedRecipes["recipe:500"] = true
untracked.professions.alchemy.learnedRecipes["recipe:500"] = true

local service = GamersTrackerForever.CraftabilityService:Create(repo, { now = function() return 2000 end })
local result = service:Calculate(recipe, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(result.reagents[1].availableNow.status, "short", "known bag short is confirmed despite unscanned bank")
same(result.reagents[1].availableNow.owned, 4, "current known bag total")
same(result.reagents[1].afterTransfer.owned, 12, "compatible pooled total")
same(result.reagents[1].afterTransfer.shortage, 0, "pooled shortage")
same(result.reagents[1].afterTransfer.status, "stale", "stale contribution is labelled")
same(result.craftableAfterTransfer, 1, "maximum craft count")
assert(result.canCraft and result.basedOnStaleData)
same(result.reagents[1].availableNow.bankCount, 0, "bank is shown but not counted now")
for _, row in ipairs(result.reagents[1].afterTransfer.characters) do
  if row.characterKey == "corvin" then same(row.bank, 5, "bank contributes after transfer only") end
end

local multi = service:Calculate({ name = "Two Materials", reagents = {
  { itemID = 100, quantity = 4, kind = "item" },
  { itemID = 200, quantity = 10, kind = "item" },
} }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(multi.craftableAfterTransfer, 1, "minimum craft count across reagents")
same(multi.reagents[1].shortage, 0, "first reagent shortage")
same(multi.reagents[2].shortage, 0, "second reagent shortage")

-- A known bag total satisfying the requirement makes an unknown bank
-- irrelevant for that reagent.
local bagSatisfied = service:Calculate({ name = "Bag-only", reagents = { { itemID = 100, quantity = 4, kind = "item" } } }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(bagSatisfied.reagents[1].availableNow.status, "ready", "bag satisfaction exception")

-- Once every eligible storage snapshot is known, zero holdings are a confirmed
-- shortage rather than unknown.
empty.identity.transferGroup = "empty"
local zero = service:Calculate({ name = "Empty", reagents = { { itemID = 999, quantity = 1, kind = "item" } } }, product.characters, { currentCharacterKey = "empty", transferGroup = "empty" })
same(zero.reagents[1].availableNow.status, "short", "known zero holdings")
same(zero.reagents[1].afterTransfer.status, "short", "known pooled zero holdings")
local perReagent = service:Calculate({ name = "Two Shortages", reagents = {
  { itemID = 998, quantity = 2, kind = "item" },
  { itemID = 999, quantity = 3, kind = "item" },
} }, product.characters, { currentCharacterKey = "empty", transferGroup = "empty" })
same(perReagent.reagents[1].shortage, 2, "first per-reagent shortage")
same(perReagent.reagents[2].shortage, 3, "second per-reagent shortage")

-- Incompatible and untracked characters are represented in rows but never
-- contribute to the pool.
local rows = result.reagents[1].afterTransfer.characters
local byKey = {}
for _, row in ipairs(rows) do byKey[row.characterKey] = row end
assert(byKey.isolated and not byKey.isolated.included and byKey.isolated.bags == 100)
assert(byKey.untracked == nil, "untracked character must not enter material rows")
same(result.reagents[1].afterTransfer.owned, 12, "incompatible material excluded")

local special = service:Calculate({ name = "Tool Recipe", reagents = { { itemID = 100, quantity = 1, kind = "item" } }, specialRequirements = { tool = true } }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(special.status, "special requirement", "special requirement blocks false-ready")
assert(not special.canCraft and special.craftableAfterTransfer == 12)
local unknown = service:Calculate({ name = "Unknown Recipe", reagents = { { quantity = 1, kind = "unknown" } } }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(unknown.status, "unknown", "unknown requirement blocks false-ready")
assert(not unknown.canCraft)
local missingReagents = service:Calculate({ name = "Incomplete Recipe" }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(missingReagents.availableNow.status, "unknown", "missing reagent field is incomplete")
same(missingReagents.afterTransfer.status, "unknown", "missing reagent field is unknown after transfer")
assert(missingReagents.incompleteRecipeData and not missingReagents.canCraft)
local emptyReagents = service:Calculate({ name = "No Materials", reagents = {} }, product.characters, { currentCharacterKey = "ana", transferGroup = "realm|alliance" })
same(emptyReagents.availableNow.status, "ready", "explicit empty reagent table is valid")
local priorityResult = service:Calculate({ name = "Status Priority", reagents = {
  { itemID = 100, quantity = 1, kind = "item" },
  { itemID = 999, quantity = 1, kind = "item" },
} }, product.characters, { currentCharacterKey = "priority", transferGroup = "priority" })
same(priorityResult.reagents[1].afterTransfer.status, "stale", "first reagent is stale")
same(priorityResult.reagents[2].afterTransfer.status, "short", "later reagent is short")
same(priorityResult.afterTransfer.status, "short", "shortage overrides stale summary")
local unknownPriority = service:Calculate({ name = "Unknown Priority", reagents = {
  { itemID = 100, quantity = 1, kind = "item" },
  { itemID = 999, quantity = 1, kind = "item" },
  { kind = "unknown", quantity = 1 },
} }, product.characters, { currentCharacterKey = "priority", transferGroup = "priority" })
same(unknownPriority.reagents[1].afterTransfer.status, "stale", "unknown test starts with stale")
same(unknownPriority.reagents[2].afterTransfer.status, "short", "unknown test includes short")
same(unknownPriority.reagents[3].status, "unknown", "unknown requirement status")
same(unknownPriority.afterTransfer.status, "unknown", "unknown overrides earlier short and stale")
local unscannedResult = service:Calculate({ name = "Bank Only", reagents = { { itemID = 100, quantity = 1, kind = "item" } } }, product.characters, { currentCharacterKey = "unscanned-bags", transferGroup = "unscanned" })
same(unscannedResult.availableNow.status, "unknown", "unscanned bags make now unknown")
same(unscannedResult.afterTransfer.status, "ready", "known bank contributes after transfer")
same(unscannedResult.availableNow.owned, 0, "unscanned bags contribute no now count")
same(unscannedResult.afterTransfer.owned, 99, "bank-only after-transfer count")

-- Catalog queries are deterministic, deduplicated, and support the UI filters.
local catalog = GamersTrackerForever.RecipeCatalog:Create(repo, { productKey = "classic_era", craftabilityService = service })
local all = catalog:ListRecipes({ productKey = "classic_era" })
same(#all, 1, "deduplicated catalog")
same(all[1].knownCount, 3, "tracked known-by list includes isolated tracked character")
same(all[1].professionName, "Alchemy", "profession name resolved from character record")
same(#catalog:GetKnownByCharacters("classic_era", "item:900"), 3, "known-by alias query")
same(#catalog:GetKnownByCharacters("classic_era", "recipe:500", { includeUntracked = true }), 4, "optional untracked known-by query")
same(#catalog:ListRecipes({ productKey = "classic_era", transferGroup = "realm|alliance", transferOnly = true }), 1, "transfer ecosystem filter")
same(#catalog:ListRecipes({ productKey = "classic_era", search = "transmute", profession = "alchemy" }), 1, "text and profession filters")
local craftable = catalog:ListRecipes({ productKey = "classic_era", calculate = true, currentCharacterKey = "ana", transferGroup = "realm|alliance", craftability = "craftable" })
same(#craftable, 1, "craftability filter includes stale-but-usable result")

print("GamersTrackerForever Task 5 catalog/craftability harness: PASS")
