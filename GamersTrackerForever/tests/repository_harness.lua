-- Lua 5.1 fixture tests for Task 2 persistence and recovery behavior.

local root = "."
local files = {
  root .. "/Constants.lua",
  root .. "/Repository.lua",
  root .. "/ViewModels.lua",
}
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local env = {}
local repo = GamersTrackerForever.Repository:Create(env)

-- Missing SavedVariables creates the exact version-1 root defaults.
local db = repo:Initialize(nil)
assert(db.schemaVersion == 1)
assert(db.settings.staleAfterSeconds == 86400)
assert(db.settings.veryStaleAfterSeconds == 604800)
assert(db.settings.maxTrackedCharacters == nil, "new installs must not store a character limit")
assert(type(db.products) == "table" and next(db.products) == nil)
assert(env.GamersTrackerForeverDB == db)

-- A pre-rename database is copied to the new SavedVariables global once.
local legacyRoot = { products = { classic_era = { characters = { legacy = { level = 17 } } } } }
local legacyEnv = { AltCraftTrackerDB = legacyRoot }
local legacyRepo = GamersTrackerForever.Repository:Create(legacyEnv)
local legacyMigrated = legacyRepo:Initialize()
assert(legacyMigrated.products.classic_era.characters.legacy.level == 17)
assert(legacyEnv.GamersTrackerForeverDB == legacyMigrated)
assert(legacyMigrated ~= legacyRoot)
assert(legacyEnv.AltCraftTrackerDB == legacyRoot)
assert(legacyRepo:GetDiagnostics().legacySavedVariables == true)

-- Product/character keys are supplied by the adapter/current context.
assert(repo:CommitCharacterContext({
  productKey = "classic_era",
  characterKey = "realm|ana|alliance",
  identity = { guid = "", displayName = "Ana", realm = "Realm", faction = "Alliance", transferGroup = "realm|alliance" },
  client = { productID = 2, version = "1.15.9", build = "63830", interface = 11509 },
  level = 42,
}, 1000))
local character = repo:GetCharacter("classic_era", "realm|ana|alliance")
assert(character.level == 42 and character.identity.displayName == "Ana")
assert(character.tracked == true)
assert(not repo:SetMaxTrackedCharacters(1), "old limit controls must not reactivate a cap")
assert(repo:GetMaxTrackedCharacters() == nil, "automatic tracking has no count cap")
assert(not repo:SetTracked("classic_era", "realm|ana|alliance", false), "characters cannot be opted out")
assert(character.tracked == true, "legacy opt-out calls must preserve automatic tracking")
assert(repo:GetProduct("forever", true) ~= repo:GetProduct("classic_era", true))

-- Valid snapshot commits replace a complete snapshot atomically.
assert(repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bags = { [123] = 4 },
  bank = { [123] = 20 },
  bagsScannedAt = 1001,
  bankScannedAt = 1002,
}))
assert(character.inventory.bags[123] == 4 and character.inventory.bank[123] == 20)
local beforeBank = character.inventory.bank[123]
assert(not repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", { complete = false, bags = { [123] = 99 } }))
assert(character.inventory.bags[123] == 4 and character.inventory.bank[123] == beforeBank)
assert(repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bankAccessible = false,
  bags = { [123] = 6 },
  bagsScannedAt = 1003,
}))
assert(character.inventory.bags[123] == 6 and character.inventory.bank[123] == beforeBank)
assert(repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bags = { [123] = 8 },
  bagsScannedAt = 1006,
}))
assert(character.inventory.bags[123] == 8 and character.inventory.bank[123] == beforeBank)
assert(repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bank = { [123] = 30 },
  bankScannedAt = 1007,
}))
assert(character.inventory.bags[123] == 8 and character.inventory.bank[123] == 30)
assert(not repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bags = { [0] = 1 },
}))
assert(not repo:CommitInventorySnapshot("classic_era", "realm|ana|alliance", {
  complete = true,
  bags = { [123] = -1 },
}))
assert(repo:CommitBagsSnapshot("classic_era", "realm|ana|alliance", { [123] = 0, [456] = 3 }, 1008))
assert(character.inventory.bags[123] == nil and character.inventory.bags[456] == 3)

assert(repo:CommitProfessionSnapshot("classic_era", "realm|ana|alliance", "alchemy", {
  complete = true,
  professionID = 171,
  name = "Alchemy",
  rank = 225,
  maxRank = 300,
  learnedRecipes = { ["recipe:1"] = true },
  skillScannedAt = 1004,
  recipesScannedAt = 1005,
  scanState = "current",
}))
assert(character.professions.alchemy.rank == 225)
assert(not repo:CommitProfessionSnapshot("classic_era", "realm|ana|alliance", "alchemy", { complete = false, rank = 1 }))
assert(character.professions.alchemy.rank == 225)
local learnedBeforeSkill = character.professions.alchemy.learnedRecipes["recipe:1"]
local recipesScannedBeforeSkill = character.professions.alchemy.recipesScannedAt
assert(repo:CommitProfessionSkillSnapshot("classic_era", "realm|ana|alliance", "alchemy", {
  name = "Alchemy",
  rank = 230,
  maxRank = 300,
  skillScannedAt = 1009,
}))
assert(character.professions.alchemy.rank == 230)
assert(character.professions.alchemy.learnedRecipes["recipe:1"] == learnedBeforeSkill)
assert(character.professions.alchemy.recipesScannedAt == recipesScannedBeforeSkill)
assert(character.professions.alchemy.scanState == "current")
assert(not repo:CommitLearnedRecipeSet("classic_era", "realm|ana|alliance", nil, {}, 1010))

-- A mixed fixture preserves healthy records while recovering corrupt records.
local mixed = {
  schemaVersion = 1,
  settings = { staleAfterSeconds = 60 },
  products = {
    healthy = {
      dataVersion = 1,
      recipes = { good = { recipeID = 7, name = "Good", reagents = { { itemID = 123, quantity = 2,
        name = "Known Material", link = "|Hitem:123:0|h[Known Material]|h", icon = 456 } } } },
      characters = { keep = { tracked = true, level = 10, identity = { displayName = "Keep" } } },
    },
    corruptProduct = "not a product",
    partial = { characters = { bad = "not a character", okay = { level = 12 } } },
  },
}
local recovered = GamersTrackerForever.Repository:Create({}):Initialize(mixed)
assert(recovered.schemaVersion == 1 and recovered.settings.veryStaleAfterSeconds == 604800)
assert(recovered.products.healthy.characters.keep.level == 10)
assert(recovered.products.healthy.recipes.good.recipeID == 7)
assert(recovered.products.healthy.recipes.good.reagents[1].name == "Known Material")
assert(recovered.products.healthy.recipes.good.reagents[1].icon == 456)
assert(recovered.products.corruptProduct == nil)
assert(recovered.products.partial.characters.bad == nil)
assert(recovered.products.partial.characters.okay.level == 12)
assert(recovered.products.partial.characters.okay.tracked == true)
assert(#repo:GetDiagnostics().quarantined == 0) -- previous repository remains unaffected
local recoveryRepo = GamersTrackerForever.Repository:Create({})
recoveryRepo:Initialize(mixed)
assert(#recoveryRepo:GetDiagnostics().quarantined > 0)

-- An existing account can have more than the old cap and opted-out records.
-- Loading it must retain all snapshots and activate all discovered characters.
local formerlyLimited = { schemaVersion = 1, settings = { maxTrackedCharacters = 1 }, products = {
  classic_era = { characters = {
    first = { tracked = true, level = 20, professions = { smith = { name = "Blacksmithing", rank = 50 } } },
    second = { tracked = false, level = 30, inventory = { bags = { [2840] = 8 }, bagsScannedAt = 900 } },
    third = { tracked = false, level = 40 },
  } },
} }
local unlimitedRepo = GamersTrackerForever.Repository:Create({})
local unlimitedDB = unlimitedRepo:Initialize(formerlyLimited)
assert(unlimitedDB.settings.maxTrackedCharacters == nil)
local members = unlimitedDB.products.classic_era.characters
assert(members.first.tracked and members.second.tracked and members.third.tracked)
assert(members.first.professions.smith.rank == 50 and members.second.inventory.bags[2840] == 8)
assert(unlimitedRepo:CommitCharacterContext({ productKey = "classic_era", characterKey = "fourth", level = 10 }, 1000))
assert(members.fourth.tracked == true, "new characters are tracked beyond the old limit")
local selector = GamersTrackerForever.ViewModels.BuildCharacterSelector(unlimitedDB.products.classic_era,
  { settings = unlimitedDB.settings })
assert(#selector.characters == 4 and selector.trackedCount == 4)
assert(selector.maxTrackedCharacters == nil and selector.trackLimitLabel == nil)
assert(selector.header == "Characters 4")

-- A corrupt root is recoverable without leaving a malformed SavedVariables table.
local rootRepo = GamersTrackerForever.Repository:Create({})
local reset = rootRepo:Initialize("corrupt root")
assert(reset.schemaVersion == 1 and type(reset.products) == "table")
assert(#rootRepo:GetDiagnostics().errors > 0)

-- Versioned migration accepts a missing schema version and retains records.
local migrationRepo = GamersTrackerForever.Repository:Create({})
local migrated = migrationRepo:Initialize({ products = { classic_era = { characters = { c = { level = 8 } } } } })
assert(migrated.schemaVersion == 1)
assert(migrated.products.classic_era.characters.c.level == 8)
assert(migrationRepo:GetDiagnostics().migrated == true)

-- Recipe definitions are product-level and replaced only after validation.
assert(migrationRepo:CommitRecipeSnapshot("classic_era", "r1", {
  complete = true,
  recipeID = 11,
  professionID = 171,
  name = "Potion",
  reagents = { { itemID = 123, quantity = 2, kind = "item" } },
}))
assert(migrated.products.classic_era.recipes.r1.recipeID == 11)
assert(migrationRepo:CommitRecipeSnapshot("classic_era", "r2", {
  complete = true,
  recipeID = 12,
  professionID = 171,
  name = "Bound Tool Recipe",
  categoryID = 22,
  categoryName = "Mail Leggings",
  categoryPath = { "Armor", "Mail Leggings" },
  specialRequirements = {
    tool = { itemID = 456, required = true },
    location = "forge",
  },
  unknownRequirements = { reason = "client-specific" },
  reagents = {
    {
      itemID = 123,
      quantity = 2,
      kind = "item",
      soulbound = true,
      currency = false,
      tool = true,
      locationBound = true,
      quality = 3,
      substitutable = false,
      unknownRequirements = { quality = true },
    },
  },
}))
local metadataRecipe = migrated.products.classic_era.recipes.r2
assert(metadataRecipe.specialRequirements.tool.itemID == 456)
assert(metadataRecipe.specialRequirements.tool.required == true)
assert(metadataRecipe.unknownRequirements.reason == "client-specific")
assert(metadataRecipe.categoryID == 22 and metadataRecipe.categoryName == "Mail Leggings")
assert(metadataRecipe.categoryPath[1] == "Armor" and metadataRecipe.categoryPath[2] == "Mail Leggings")
local metadataReagent = metadataRecipe.reagents[1]
assert(metadataReagent.kind == "item" and metadataReagent.soulbound == true and metadataReagent.currency == false)
assert(metadataReagent.tool == true and metadataReagent.locationBound == true and metadataReagent.quality == 3)
assert(metadataReagent.substitutable == false and metadataReagent.unknownRequirements.quality == true)
local reloaded = migrationRepo:Initialize(migrated)
local reloadedRecipe = reloaded.products.classic_era.recipes.r2
assert(reloadedRecipe.specialRequirements.location == "forge")
assert(reloadedRecipe.categoryPath[1] == "Armor" and reloadedRecipe.categoryName == "Mail Leggings")
assert(reloadedRecipe.reagents[1].soulbound == true and reloadedRecipe.reagents[1].tool == true)

-- A newer schema is retained verbatim and exposed read-only for downgrade safety.
local futureRoot = { schemaVersion = 99, sentinel = "future-data", products = { future = "opaque" } }
local futureEnv = { GamersTrackerForeverDB = futureRoot }
local futureRepo = GamersTrackerForever.Repository:Create(futureEnv)
assert(futureRepo:Initialize() == futureRoot)
assert(futureRepo:IsReadOnly() and futureEnv.GamersTrackerForeverDB == futureRoot)
assert(futureRoot.schemaVersion == 99 and futureRoot.sentinel == "future-data")
assert(not futureRepo:CommitCharacterContext({ productKey = "classic_era", characterKey = "future" }))
assert(not futureRepo:CommitRecipeSnapshot("classic_era", "future", { complete = true, recipeID = 1 }))
assert(not migrationRepo:CommitRecipeSnapshot("classic_era", "r1", { complete = false, recipeID = 999 }))
assert(migrated.products.classic_era.recipes.r1.recipeID == 11)

print("GamersTrackerForever Task 2 repository harness: PASS")
