-- Lua 5.1 fixture tests for Task 6 projections and a frame-construction smoke test.
local files = { "Constants.lua", "Repository.lua", "CraftabilityService.lua", "RecipeCatalog.lua", "ViewModels.lua", "UI.lua" }
for _, file in ipairs(files) do local chunk, err = loadfile(file); assert(chunk, err); chunk() end

local function same(actual, expected, message)
  assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local repo = GamersTrackerForever.Repository:Create({})
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
local service = GamersTrackerForever.CraftabilityService:Create(repo, { now = function() return 2000 end })
local catalog = GamersTrackerForever.RecipeCatalog:Create(repo, { productKey = "classic_era", craftabilityService = service })

local characterRows = GamersTrackerForever.ViewModels.BuildCharacters(product, { now = 2000, settings = db.settings, expanded = { ana = true } })
same(characterRows[1].name, "Ana", "characters sort by display name")
same(characterRows[1].lastSeenLabel, "10s ago", "age formatting")
same(characterRows[1].bagsFreshness.state, "current", "bag freshness")
same(characterRows[1].professions[1].recipeScanState, "current", "profession scan state")
assert(characterRows[1].expanded, "expanded map is projected")
local pane = GamersTrackerForever.ViewModels.BuildTwoPane(product, { now = 2000, settings = db.settings, productKey = "classic_era", selectedCharacterKey = "ana" })
same(pane.left.selectedCharacterKey, "ana", "selection is deterministic")
same(pane.left.maxTrackedCharacters, 3, "default tracking limit")
same(pane.right.inventoryRows[1].itemID, 100, "detail exposes sorted inventory rows")
same(pane.right.inventoryRows[1].bags, 4, "detail exposes bag counts")
product.characters.extra = { tracked = false, identity = { displayName = "Extra" }, inventory = { bags = {}, bank = {} } }
assert(repo:SetMaxTrackedCharacters(1))
local limited, limitError = repo:SetTracked("classic_era", "extra", true)
assert(not limited and limitError:find("tracking limit", 1, true), "tracking limit is enforced without untracking")
assert(repo:SetMaxTrackedCharacters(3))

local recipeRows = GamersTrackerForever.ViewModels.BuildRecipes(catalog, "classic_era", { search = "potion", profession = "Alchemy" })
same(#recipeRows, 1, "recipe search and profession filters")
same(recipeRows[1].knownLabel, "Ana, Corvin", "known-by label")
local calc = service:Calculate(product.recipes["recipe:1"], product.characters, { currentCharacterKey = "ana", transferGroup = "realm|A", now = 2000 })
local materialRows = GamersTrackerForever.ViewModels.BuildMaterialRows(product.recipes["recipe:1"], calc, { itemResolver = function() return "Test Reagent", nil, 123 end })
same(materialRows[1].required, 10, "material requirement")
same(materialRows[1].pooledOwned, 24, "pooled material total")
same(materialRows[1].status, "stale", "stale material status")
same(materialRows[1].nowOwned, 4, "available-now bags-only total")
same(materialRows[1].nowShortage, 6, "available-now shortage")
same(materialRows[1].nowStatus, "short", "available-now status")
same(materialRows[1].afterTransferOwned, 24, "after-transfer pooled total")
same(materialRows[1].afterTransferShortage, 0, "after-transfer shortage")
same(materialRows[1].afterTransferStatus, "stale", "after-transfer status")
same(GamersTrackerForever.ViewModels.FormatAvailability(calc.availableNow), "short (0 crafts)", "render-ready now summary")
same(GamersTrackerForever.ViewModels.FormatAvailability(calc.afterTransfer), "stale (2 crafts)", "render-ready transfer summary")
same(#materialRows[1].characters, 3, "all tracked characters represented, including isolated")
local cell, meta = GamersTrackerForever.ViewModels.FormatMaterialCell(materialRows[1].characters[1], "bank", { date = function(_, stamp) return "DATE:" .. tostring(stamp) end })
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
local dropdownWidth, dropdownText
_G.UIDropDownMenu_Initialize = function() end
_G.UIDropDownMenu_CreateInfo = function() return {} end
_G.UIDropDownMenu_AddButton = function() end
-- Regression guard: SoD/Classic signatures are (frame, value), not reversed.
_G.UIDropDownMenu_SetWidth = function(frame, width)
  assert(type(frame) == "table", "UIDropDownMenu_SetWidth must receive frame first")
  dropdownWidth = width; frame.dropdownWidth = width
end
_G.UIDropDownMenu_SetText = function(frame, value)
  assert(type(frame) == "table", "UIDropDownMenu_SetText must receive frame first")
  dropdownText = value; frame.dropdownText = value
end
local ui = GamersTrackerForever.UI:Create({ env = { time = function() return 2000 end }, repository = repo, catalog = catalog, craftabilityService = service, productKey = "classic_era" })
ui:Initialize()
assert(ui.frame and ui.initialized and ui.title and ui.characterScroll, "mocked-frame UI initializes")
same(ui.frame.w, 900, "native UI default width")
same(ui.frame.h, 560, "native UI default height")
same(dropdownWidth, 92, "dropdown width uses frame-first SoD signature")
same(dropdownText, "3", "dropdown text uses frame-first SoD signature")
ui.tab = "recipes"; ui:Refresh(); assert(ui.recipeScroll and ui.recipeContent, "recipes tab renders")

print("GamersTrackerForever Task 6 UI/view-model harness: PASS")
