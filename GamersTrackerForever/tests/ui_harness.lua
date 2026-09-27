-- Lua 5.1 fixture tests for Task 6 projections and a frame-construction smoke test.
local files = { "Constants.lua", "Repository.lua", "CraftabilityService.lua", "RecipeCatalog.lua", "ViewModels.lua", "ClassIcons.lua", "ItemUsability.lua", "UI.lua" }
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
product.recipes["recipe:1"] = { recipeID = 1, professionID = 171, name = "Test Potion",
  categoryName = "Healing", categoryPath = { "Potions", "Healing" },
  outputItemID = 900, reagents = { { itemID = 100, quantity = 10, kind = "item" } } }
product.recipes["recipe:2"] = { recipeID = 2, professionID = 164, name = "Copper Buckle", reagents = {} }
local service = GamersTrackerForever.CraftabilityService:Create(repo, { now = function() return 2000 end })
local catalog = GamersTrackerForever.RecipeCatalog:Create(repo, { productKey = "classic_era", craftabilityService = service })

local characterRows = GamersTrackerForever.ViewModels.BuildCharacters(product, { now = 2000, settings = db.settings, expanded = { ana = true } })
same(characterRows[1].name, "Ana", "characters sort by display name")
same(characterRows[1].lastSeenLabel, "10s ago", "age formatting")
same(characterRows[1].bagsFreshness.state, "current", "bag freshness")
same(characterRows[1].professions[1].recipeScanState, "current", "profession scan state")
same(characterRows[1].professions[1].recipes[1].name, "Test Potion", "learned recipe appears under profession")
same(characterRows[1].professions[1].recipes[1].categoryPath[1], "Potions", "category ancestry reaches UI")
same(characterRows[1].professions[1].learnedCount, 1, "learned recipe count uses true entries")
assert(characterRows[1].expanded, "expanded map is projected")
local pane = GamersTrackerForever.ViewModels.BuildTwoPane(product, { now = 2000, settings = db.settings, productKey = "classic_era", selectedCharacterKey = "ana" })
same(pane.left.selectedCharacterKey, "ana", "selection is deterministic")
same(pane.left.trackedCount, 3, "all discovered characters are tracked")
same(pane.right.inventoryRows[1].itemID, 100, "detail exposes sorted inventory rows")
same(pane.right.inventoryRows[1].bags, 4, "detail exposes bag counts")
product.characters.extra = { tracked = false, identity = { displayName = "Extra" }, inventory = { bags = {}, bank = {} } }
assert(repo:SetTracked("classic_era", "extra", true), "discovered character may be tracked without a count limit")

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
same(#materialRows[1].characters, 4, "all tracked characters represented, including isolated")
local specialRows = GamersTrackerForever.ViewModels.BuildMaterialRows(
  { reagents = { { name = "Anvil", kind = "tool" } } },
  { reagents = { { itemID = nil, quantity = 1, kind = "special" } } })
same(specialRows[1].name, "Anvil", "special requirement never renders as Item nil")
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
  function f:SetBackdrop(value) self.backdrop = value end
  function f:SetBackdropColor(...) self.backdropColor = { ... } end
  function f:SetScrollChild(v) self.child = v end
  function f:SetAutoFocus() end; function f:SetTextInsets() end; function f:SetHighlightTexture() end; function f:ClearFocus() end
  function f:SetText(v) self.text = v end; function f:GetText() return self.text or "" end
  function f:SetTexture(v) self.texture = v end
  function f:SetTexCoord(...) self.texCoord = { ... } end
  function f:CreateFontString()
    local fontString = mockFrame()
    self.fontStrings = self.fontStrings or {}
    self.fontStrings[#self.fontStrings + 1] = fontString
    return fontString
  end
  function f:CreateTexture()
    local texture = mockFrame()
    self.textures = self.textures or {}
    self.textures[#self.textures + 1] = texture
    return texture
  end
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
local tooltipLink, tooltipHidden, comparedTooltip, tooltipOwner, tooltipAnchor
_G.GameTooltip = {
  SetOwner = function(_, owner, anchor) tooltipOwner = owner; tooltipAnchor = anchor end,
  ClearAllPoints = function() end,
  SetPoint = function(_, point, relativeFrame, relativePoint, x, y)
    tooltipAnchor = { point, relativeFrame, relativePoint, x, y }
  end,
  SetHyperlink = function(_, link) tooltipLink = link end,
  Show = function() end,
  Hide = function() tooltipHidden = true end,
}
_G.GameTooltip_ShowCompareItem = function(tooltip) comparedTooltip = tooltip end
-- Some clients include the profession itself as the first category ancestor.
-- The UI should render it once as the profession header, not twice.
product.recipes["recipe:1"].categoryPath = { "Alchemy", "Potions", "Healing" }
local ui = GamersTrackerForever.UI:Create({ env = {
  time = function() return 2000 end,
  GetItemInfo = function() return "Test Reagent", nil, nil, nil, nil, nil, nil, nil, nil, 555 end,
}, repository = repo, catalog = catalog, craftabilityService = service, productKey = "classic_era" })
ui:Initialize()
assert(ui.frame and ui.initialized and ui.title and ui.characterScroll, "mocked-frame UI initializes")
same(ui.frame.w, 900, "native UI default width")
same(ui.frame.h, 560, "native UI default height")
same(ui.frame.backdrop.bgFile, "Interface\\Buttons\\WHITE8X8", "solid native backdrop keeps world and chat legible")
assert(ui.characterSearch and ui.characterSearchClear and not ui.trackLimitDropdown,
  "left search replaces the tracking-limit dropdown")
same(ui.leftPane.backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border",
  "profession-like left panel has a distinct framed border")
same(ui.searchIcon.texture, "Interface\\Common\\UI-Searchbox-Icon",
  "search control has a native search icon")
assert(not ui.tabs.characters and ui.tabs.recipes.text == "All Recipes"
  and ui.tabs.recipes.point[1] == "TOPLEFT", "redundant Characters tab is removed without a header gap")
local sawMageIcon = false
for _, row in ipairs(ui.rows or {}) do
  if row.classIcon and row.classIcon.texture == GamersTrackerForever.ClassIcons.TEXTURE then
    sawMageIcon = true
    same(row.classIcon.texCoord[1], 0.25, "Mage class icon uses the Blizzard sprite")
  end
end
assert(sawMageIcon, "known character class gets a small icon in the left tree")
local function treeContains(needle)
  for _, row in ipairs(ui.rows or {}) do
    local caption = row.fontStrings and row.fontStrings[1] and row.fontStrings[1].text or row.text
    if tostring(caption or ""):find(needle, 1, true) then return true end
  end
  return false
end
assert(not treeContains("Test Potion"), "collapsed profession initially hides its recipe")
ui.characterSearch:SetText("PoTiOn")
ui.characterSearch.scripts.OnTextChanged()
assert(treeContains("Ana") and treeContains("Corvin") and treeContains("Test Potion"),
  "case-insensitive recipe search shows matching recipes and ancestor characters")
assert(not treeContains("Isolated"), "recipe search filters unrelated characters")
assert(ui.expandedProfessions["ana|alchemy"] == nil, "search does not change expansion preference")
ui.characterSearch:SetText("Corvin")
ui.characterSearch.scripts.OnTextChanged()
assert(treeContains("Corvin") and treeContains("Alchemy") and treeContains("Test Potion")
  and not treeContains("Ana"), "character search shows its descendant professions and recipes")
ui.characterSearch:SetText("Alchemy")
ui.characterSearch.scripts.OnTextChanged()
assert(treeContains("Ana") and treeContains("Corvin") and treeContains("Test Potion"),
  "profession search shows ancestor characters and descendant recipes")
ui.characterSearchClear.scripts.OnClick()
assert(ui.characterSearch:GetText() == "" and not treeContains("Test Potion")
  and ui.expandedProfessions["ana|alchemy"] == nil,
  "clear restores collapsed expansion without changing it")
assert(not treeContains("[tracked]") and not treeContains("[available]"),
  "all discovered characters are shown without obsolete tracking badges")
for _, row in ipairs(ui.detailRows or {}) do
  assert(not tostring(row.text or ""):find("Saved inventory", 1, true)
    and not tostring(row.text or ""):find("Item 100", 1, true), "overview must not dump raw inventory")
  assert(row.text ~= "Track" and row.text ~= "Untrack" and row.text ~= "Forget",
    "manual tracking and Forget controls are removed")
end
ui:ToggleProfession("ana", "alchemy")
assert(ui.expandedProfessions["ana|alchemy"] and ui.selectedProfessionKey == "alchemy",
  "profession expands beneath the selected character")
assert(treeContains("Potions") and treeContains("Healing") and treeContains("Test Potion"),
  "native category hierarchy renders under the profession")
local headerKinds, duplicateRoot = {}, false
for _, row in ipairs(ui.rows or {}) do
  if row.gtfStyle and row.gtfStyle ~= "plain" then
    headerKinds[row.gtfStyle] = true
    if row.gtfStyle ~= "recipe" then
      assert(row.gtfBar and row.gtfExpander, "tree headers use full-width bars and right-side expanders")
    end
    if row.gtfStyle == "category" and row.gtfLabel.text == "Alchemy" then duplicateRoot = true end
  end
end
assert(headerKinds.character and headerKinds.profession and headerKinds.category and headerKinds.recipe,
  "character, profession, category, and recipe rows have distinct native-like styles")
assert(not duplicateRoot, "category path does not repeat the profession root")
local categoryKey = "ana|alchemy\031Potions"
ui:ToggleCategory(categoryKey)
assert(ui.expandedCategories[categoryKey] == false and treeContains("Potions")
  and not treeContains("Healing") and not treeContains("Test Potion"),
  "collapsing a category hides descendant categories and recipes")
ui.characterSearch:SetText("healing")
ui.characterSearch.scripts.OnTextChanged()
assert(treeContains("Ana") and treeContains("Alchemy") and treeContains("Potions")
  and treeContains("Healing") and treeContains("Test Potion"),
  "searching by native category shows matching recipes and all ancestors")
ui.characterSearchClear.scripts.OnClick()
assert(ui.expandedCategories[categoryKey] == false and not treeContains("Test Potion"),
  "clearing search restores category collapse preference")
ui:ToggleCategory(categoryKey)
assert(treeContains("Test Potion"), "reopening a category restores its recipes")
ui:SelectRecipe("ana", "alchemy", "recipe:1")
assert(ui.selectedRecipeKey == "recipe:1" and #ui.materialCards == 1,
  "recipe selection renders a material card")
assert(ui.sourcePanel and ui.sourcePanel ~= ui.detailRows[1],
  "item detail and material holders use separate framed panels")
for _, row in ipairs(ui.detailRows or {}) do
  local caption = tostring(row.text or "")
  assert(not caption:find("Ana — level", 1, true)
    and not caption:find("Last seen:", 1, true)
    and not caption:find("Now:", 1, true)
    and caption ~= "Forget", "item page does not repeat character or craftability summary")
end
for _, field in ipairs(ui.detailRows[1].fontStrings or {}) do
  assert(not tostring(field.text or ""):find("Alchemy 225/300", 1, true),
    "item panel omits profession rank")
end
assert(not tostring(ui.materialCards[1].fontStrings[1].text):find("Item 100", 1, true),
  "material caption shows a name, not a numeric item ID")
local testSubclass = 3 -- mail armor is permanently unavailable to Priests
ui.env.UnitClass = function() return "Priest", "PRIEST", 5 end
ui.env.GetItemInfoInstant = function(itemID)
  if itemID == 900 then return 900, "Armor", "Mail", "INVTYPE_CHEST", nil, 4, testSubclass end
end
ui:Refresh()
assert(treeContains("Test Potion |cffff4040×|r"), "red cross follows logged-in Priest, not saved Mage crafter")
local sawDetailCross = false
for _, row in ipairs(ui.detailRows or {}) do
  if tostring(row.text or ""):find("Test Potion |cffff4040×|r", 1, true) then sawDetailCross = true end
end
assert(sawDetailCross, "selected recipe detail also marks confirmed unwearable output")
testSubclass = 1 -- cloth is not crossed out
ui:Refresh()
assert(not treeContains("Test Potion |cffff4040×|r"), "allowed armor is not crossed out")
assert(ui.outputItemButton and type(ui.outputItemButton.scripts.OnEnter) == "function",
  "crafted item icon must offer a native item tooltip")
ui.outputItemButton.scripts.OnEnter(ui.outputItemButton)
same(tooltipLink, "item:900", "crafted item tooltip uses saved output item ID")
same(tooltipOwner, ui.outputItemButton, "crafted item tooltip is owned by the hovered icon")
same(tooltipAnchor[1], "TOPLEFT", "item tooltip starts beside the icon")
same(tooltipAnchor[2], ui.outputItemButton, "item tooltip is anchored to the hovered icon")
same(tooltipAnchor[3], "TOPRIGHT", "item tooltip sits to the icon's right")
same(tooltipAnchor[4], 6, "item tooltip uses a small horizontal gap")
same(tooltipAnchor[5], 0, "item tooltip aligns vertically with the icon")
same(comparedTooltip, GameTooltip, "native equipped-item comparison is requested when available")
ui.outputItemButton.scripts.OnLeave(ui.outputItemButton)
assert(tooltipHidden, "crafted item tooltip hides when the pointer leaves")
tooltipLink = nil
assert(type(ui.materialCards[1].scripts.OnEnter) == "function",
  "material card must offer a native item tooltip")
ui.materialCards[1].scripts.OnEnter(ui.materialCards[1])
same(tooltipLink, "item:100", "material tooltip uses saved reagent item ID")
same(tooltipAnchor[2], ui.materialCards[1], "material tooltip is anchored to its card")
same(tooltipAnchor[3], "TOPLEFT", "material tooltip starts beside the reagent icon")
same(tooltipAnchor[4], 38, "material tooltip uses the icon edge, not the full card width")
local recipeTreeTooltip = false
for _, row in ipairs(ui.rows or {}) do
  if type(row.scripts.OnEnter) == "function" then
    tooltipLink = nil
    row.scripts.OnEnter(row)
    if tooltipLink == "item:900" then recipeTreeTooltip = true; break end
  end
end
assert(recipeTreeTooltip, "recipe rows also show the crafted item tooltip")
same(ui.materialCards[1].textures[1].texture, 555, "material card uses the item texture, not item quality")
same(#ui.sourceCards, 1, "only characters with positive known holdings get cards")
same(#ui.sourceRows, 1, "zero and unknown holdings do not clutter the subpanel")
same(ui.sourceRows[1].gtfOwned, 24, "character material amount includes known bags and bank")
same(ui.sourceRows[1].gtfCharacterKey, "ana", "holding stays grouped under its nickname")
assert(ui.sourceRows[1].gtfItemButton and type(ui.sourceRows[1].gtfItemButton.scripts.OnEnter) == "function",
  "holding icon keeps the native item tooltip")
ui:SelectCharacter("ana")
assert(ui.selectedRecipeKey == nil, "selecting a character returns to its overview")
same(#ui.sourceCards, 0, "character overview clears stale item-holder cards")
ui.tab = "recipes"; ui:Refresh(); assert(ui.recipeScroll and ui.recipeContent, "recipes tab renders")
ui:SelectCharacter("ana")
same(ui.tab, "characters", "selecting a character exits the all-recipes view without a Characters tab")
ui.tab = "recipes"; ui:Refresh()
-- Filter callbacks used to invoke RefreshRecipes without its product arguments,
-- leaving the pane blank and raising a nil-product Lua error.
assert(type(ui.recipeSearch.scripts.OnTextChanged) == "function")
ui.recipeSearch:SetText("potion")
ui.recipeSearch.scripts.OnTextChanged()
assert(ui.recipeContent:GetHeight() > 1, "filter edit renders recipes without a nil product")
ui:RefreshRecipes()
assert(ui.recipeContent:GetHeight() > 1, "direct recipe refresh resolves product context")

-- Multiple owners and reagents must form character cards, not a matrix of
-- zero rows or repeated per-material headings.
product.recipes["recipe:3"] = { recipeID = 3, professionID = 171, name = "Mixed Supplies",
  outputItemID = 901, reagents = { { itemID = 100, quantity = 1, kind = "item" },
    { itemID = 200, quantity = 2, kind = "item" } } }
product.characters.ana.professions.alchemy.learnedRecipes["recipe:3"] = true
product.characters.corvin.inventory.bags = { [200] = 3 }
product.characters.corvin.inventory.bagsScannedAt = 1999
ui:SelectRecipe("ana", "alchemy", "recipe:3")
same(#ui.sourceCards, 2, "two positive owners render as two nickname cards")
same(#ui.sourceRows, 2, "each owner shows only the material it actually holds")
same(ui.sourceRows[1].gtfCharacterKey, "ana", "first owner groups its own material")
same(ui.sourceRows[1].gtfItemID, 100, "first owner gets correct reagent icon")
same(ui.sourceRows[2].gtfCharacterKey, "corvin", "second owner groups its own material")
same(ui.sourceRows[2].gtfItemID, 200, "second owner gets correct reagent icon")

local beta = repo:GetProduct("forever_beta", true)
beta.characters.beta = { tracked = true, identity = { displayName = "Beta Crafter" }, level = 20,
  professions = { smithing = { name = "Blacksmithing", rank = 53, maxRank = 75 } },
  inventory = { bags = { [100] = 4 }, bagsScannedAt = 2000 } }
local betaUI = GamersTrackerForever.UI:Create({ env = { time = function() return 2000 end },
  repository = repo, productKey = "forever_beta", recipesSupported = false })
betaUI:Initialize()
betaUI:ToggleProfession("beta", "smithing")
local sawPending = false
for _, row in ipairs(betaUI.rows) do
  if tostring(row.text or ""):find("Recipes pending", 1, true) then sawPending = true end
end
assert(sawPending and not betaUI.tabs.recipes:IsShown(),
  "Forever beta shows profession ranks but does not fabricate recipe choices")

print("GamersTrackerForever Task 6 UI/view-model harness: PASS")
