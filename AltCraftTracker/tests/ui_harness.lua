-- Lua 5.1 fixture tests for Task 6 projections and a frame-construction smoke test.
local files = { "Constants.lua", "Repository.lua", "CraftabilityService.lua", "RecipeCatalog.lua", "ViewModels.lua", "UI.lua" }
for _, file in ipairs(files) do local chunk, err = loadfile(file); assert(chunk, err); chunk() end

local function same(actual, expected, message)
  assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local repo = AltCraftTracker.Repository:Create({})
local db = repo:Initialize(nil); db.settings.staleAfterSeconds = 100; db.settings.veryStaleAfterSeconds = 500
local product = repo:GetProduct("classic_era", true)
product.characters = {
  ana = { tracked = true, identity = { displayName = "Ana", classID = 8, className = "Mage", faction = "Alliance", transferGroup = "realm|A" }, level = 42, lastSeenAt = 1990,
    professions = { alchemy = { name = "Alchemy", rank = 225, maxRank = 300, learnedRecipes = { ["recipe:1"] = true }, scanState = "current", skillScannedAt = 1990, recipesScannedAt = 1980 } },
    inventory = { bags = { [100] = 4 }, bank = { [100] = 20 }, bagsScannedAt = 1999, bankScannedAt = 1800 } },
  corvin = { tracked = true, identity = { displayName = "Corvin", faction = "Alliance", transferGroup = "realm|A" }, level = 35, lastSeenAt = 1000,
    professions = { alchemy = { name = "Alchemy", rank = 100, maxRank = 300, learnedRecipes = { ["recipe:1"] = true }, scanState = "never" } },
    inventory = { bags = {}, bank = {}, bagsScannedAt = 0, bankScannedAt = 0 } },
  isolated = { tracked = true, identity = { displayName = "Isolated", transferGroup = "other" }, level = 10, lastSeenAt = 1999, inventory = { bags = {}, bank = {}, bagsScannedAt = 1999, bankScannedAt = 1999 } },
}
product.recipes["recipe:1"] = { recipeID = 1, professionID = 171, name = "Test Potion", outputItemID = 900, reagents = { { itemID = 100, quantity = 10, kind = "item" } } }
product.recipes["recipe:2"] = { recipeID = 2, professionID = 164, name = "Copper Buckle", reagents = {} }
local service = AltCraftTracker.CraftabilityService:Create(repo, { now = function() return 2000 end })
local catalog = AltCraftTracker.RecipeCatalog:Create(repo, { productKey = "classic_era", craftabilityService = service })

local characterRows = AltCraftTracker.ViewModels.BuildCharacters(product, { now = 2000, settings = db.settings, expanded = { ana = true } })
same(characterRows[1].name, "Ana", "characters sort by display name")
same(characterRows[1].lastSeenLabel, "10s ago", "age formatting")
same(characterRows[1].bagsFreshness.state, "current", "bag freshness")
same(characterRows[1].professions[1].recipeScanState, "current", "profession scan state")
assert(characterRows[1].expanded, "expanded map is projected")

local recipeRows = AltCraftTracker.ViewModels.BuildRecipes(catalog, "classic_era", { search = "potion", profession = "Alchemy" })
same(#recipeRows, 1, "recipe search and profession filters")
same(recipeRows[1].knownLabel, "Ana, Corvin", "known-by label")
local calc = service:Calculate(product.recipes["recipe:1"], product.characters, { currentCharacterKey = "ana", transferGroup = "realm|A", now = 2000 })
local materialRows = AltCraftTracker.ViewModels.BuildMaterialRows(product.recipes["recipe:1"], calc, { itemResolver = function() return "Test Reagent", nil, 123 end })
same(materialRows[1].required, 10, "material requirement")
same(materialRows[1].pooledOwned, 24, "pooled material total")
same(materialRows[1].status, "stale", "stale material status")
same(materialRows[1].nowOwned, 4, "available-now bags-only total")
same(materialRows[1].nowShortage, 6, "available-now shortage")
same(materialRows[1].nowStatus, "short", "available-now status")
same(materialRows[1].afterTransferOwned, 24, "after-transfer pooled total")
same(materialRows[1].afterTransferShortage, 0, "after-transfer shortage")
same(materialRows[1].afterTransferStatus, "stale", "after-transfer status")
same(AltCraftTracker.ViewModels.FormatAvailability(calc.availableNow), "short (0 crafts)", "render-ready now summary")
same(AltCraftTracker.ViewModels.FormatAvailability(calc.afterTransfer), "stale (2 crafts)", "render-ready transfer summary")
same(#materialRows[1].characters, 3, "all tracked characters represented, including isolated")
local cell, meta = AltCraftTracker.ViewModels.FormatMaterialCell(materialRows[1].characters[1], "bank", { date = function(_, stamp) return "DATE:" .. tostring(stamp) end })
assert(cell:find("bank", 1, true) and meta.tooltip:find("scanned DATE:", 1, true), "snapshot tooltip includes location and exact time")

-- A compact mocked frame API is sufficient to prove the renderer avoids hard
-- dependencies on live Blizzard objects and constructs its frame tree.
local function mockFrame()
  local f = { shown = true, scripts = {} }
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:SetHeight(h) self.h = h end; function f:SetWidth(w) self.w = w end
  function f:GetWidth() return self.w or 1 end; function f:GetHeight() return self.h or 1 end
  function f:SetPoint(...) self.point = { ... } end; function f:ClearAllPoints() end
  function f:SetFrameStrata() end; function f:SetFrameLevel() end; function f:SetClampedToScreen() end
  function f:SetMovable() end; function f:EnableMouse() end; function f:SetResizable() end; function f:SetResizeBounds() end; function f:SetMinResize() end
  function f:RegisterForDrag() end; function f:SetScript(name, fn) self.scripts[name] = fn end; function f:StartMoving() end; function f:StopMovingOrSizing() end
  function f:Show() self.shown = true end; function f:Hide() self.shown = false end; function f:IsShown() return self.shown end; function f:SetShown(v) self.shown = v end
  function f:SetBackdrop() end; function f:SetBackdropColor() end; function f:SetScrollChild(v) self.child = v end
  function f:SetAutoFocus() end; function f:SetTextInsets() end; function f:SetHighlightTexture() end
  function f:SetText(v) self.text = v end; function f:GetText() return self.text or "" end
  function f:CreateFontString() return mockFrame() end; function f:CreateTexture() return mockFrame() end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  return f
end
_G.UIParent = mockFrame(); _G.CreateFrame = function() return mockFrame() end
local ui = AltCraftTracker.UI:Create({ env = { time = function() return 2000 end }, repository = repo, catalog = catalog, craftabilityService = service, productKey = "classic_era" })
ui:Initialize()
assert(ui.frame and ui.initialized and ui.title and ui.characterScroll, "mocked-frame UI initializes")
ui.tab = "recipes"; ui:Refresh(); assert(ui.recipeScroll and ui.recipeContent, "recipes tab renders")

print("AltCraft Tracker Task 6 UI/view-model harness: PASS")
