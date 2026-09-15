AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local UI = {}
UI.__index = UI
ACT.UI = UI

-- Bindings.xml calls this stable global; Task 7 may replace ACT.UI with the
-- configured instance after repository/service initialization.
function ACT_UI_TOGGLE()
  if ACT.UI and type(ACT.UI.Toggle) == "function" then ACT.UI:Toggle() end
end

local function safeCall(object, method, ...)
  if object and type(object[method]) == "function" then
    return pcall(object[method], object, ...)
  end
  return false
end

local function text(value, fallback)
  if value == nil or value == "" then return fallback or "" end
  return tostring(value)
end

local function now(env)
  if env and type(env.time) == "function" then return tonumber(env.time()) or 0 end
  if type(ACT.Now) == "function" then return tonumber(ACT.Now()) or 0 end
  return 0
end

local function getProduct(self)
  local key = self.productKey
  if not key and self.api and type(self.api.GetProduct) == "function" then key = self.api:GetProduct() end
  if not key and self.api and type(self.api.GetCurrentContext) == "function" then
    local context = self.api:GetCurrentContext() or {}
    key = context.productKey or context.product
  end
  key = key or ACT.product or ACT.PRODUCT_CLASSIC_ERA
  local product
  if self.repository and type(self.repository.GetProduct) == "function" then product = self.repository:GetProduct(key, false)
  elseif self.repository and self.repository.db then product = self.repository.db.products and self.repository.db.products[key] end
  return key, product or { characters = {}, recipes = {} }
end

local function geometry(self)
  if type(self.getGeometry) == "function" then
    local ok, value = pcall(self.getGeometry)
    if ok and type(value) == "table" then return value end
  end
  local db = self.repository and self.repository.db
  local value = db and db.settings and db.settings.uiGeometry
  return type(value) == "table" and value or { point = "CENTER", x = 0, y = 0, width = 610, height = 470 }
end

local function saveGeometry(self)
  if not self.frame or type(self.frame.GetPoint) ~= "function" then return end
  local point, _, relative, x, y = self.frame:GetPoint(1)
  local value = { point = point or "CENTER", relative = relative or "CENTER", x = x or 0, y = y or 0,
    width = self.frame.GetWidth and self.frame:GetWidth() or 610, height = self.frame.GetHeight and self.frame:GetHeight() or 470 }
  if type(self.setGeometry) == "function" then pcall(self.setGeometry, value) return end
  local db = self.repository and self.repository.db
  if db and db.settings then db.settings.uiGeometry = value end
end

local function label(parent, font, point, relative, x, y, width, height)
  local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  value:SetPoint(point, relative, x or 0, y or 0)
  if width then value:SetWidth(width) end
  if height then value:SetHeight(height) end
  return value
end

local function button(parent, caption, width, height)
  local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  value:SetSize(width or 90, height or 22)
  value:SetText(caption or "")
  return value
end

local function editBox(parent, width, height)
  local value = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  value:SetSize(width or 120, height or 22)
  value:SetAutoFocus(false)
  value:SetTextInsets(6, 6, 0, 0)
  return value
end

local function createBackdrop(frame)
  if not frame then return end
  if type(frame.SetBackdrop) == "function" then
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.96)
  end
end

local function hideRows(rows)
  for _, row in ipairs(rows or {}) do if row.Hide then row:Hide() end end
end

function UI:Create(options)
  options = type(options) == "table" and options or {}
  local self = setmetatable({ env = options.env or _G, repository = options.repository, catalog = options.catalog,
    craftability = options.craftabilityService or options.craftability, characterService = options.characterService,
    api = options.api, productKey = options.productKey, getGeometry = options.getGeometry, setGeometry = options.setGeometry,
    expandedCharacters = {}, expandedRecipes = {}, tab = "characters", rows = {}, recipeRows = {}, initialized = false }, UI)
  return self
end

function UI:SetDependencies(dependencies)
  dependencies = type(dependencies) == "table" and dependencies or {}
  for _, key in ipairs({ "repository", "catalog", "craftability", "craftabilityService", "characterService", "api", "productKey", "getGeometry", "setGeometry" }) do
    if dependencies[key] ~= nil then self[key] = dependencies[key] end
  end
  self.craftability = self.craftability or self.craftabilityService
  return self
end

function UI:Initialize(dependencies)
  self:SetDependencies(dependencies)
  if self.initialized then self:Refresh() return self end
  if type(CreateFrame) ~= "function" then return self end
  local frame
  local ok, value = pcall(CreateFrame, "Frame", "AltCraftTrackerFrame", UIParent, "BackdropTemplate")
  frame = ok and value or CreateFrame("Frame", "AltCraftTrackerFrame", UIParent)
  self.frame = frame
  frame:SetSize(610, 470)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetResizable(true)
  if type(frame.SetResizeBounds) == "function" then frame:SetResizeBounds(460, 320, 900, 760)
  elseif type(frame.SetMinResize) == "function" then frame:SetMinResize(460, 320) end
  createBackdrop(frame)
  local saved = geometry(self)
  frame:ClearAllPoints()
  frame:SetPoint(saved.point or "CENTER", UIParent, saved.relative or "CENTER", tonumber(saved.x) or 0, tonumber(saved.y) or 0)
  frame:SetSize(math.max(460, tonumber(saved.width) or 610), math.max(320, tonumber(saved.height) or 470))
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); saveGeometry(self) end)
  frame:SetScript("OnMouseUp", function(f, mouseButton) if mouseButton == "LeftButton" and f.isMoving then f:StopMovingOrSizing(); saveGeometry(self) end end)
  self.resizeGrip = CreateFrame("Button", nil, frame)
  self.resizeGrip:SetSize(16, 16); self.resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
  self.resizeGrip:SetScript("OnMouseDown", function(f, mouseButton) if mouseButton == "LeftButton" and type(frame.StartSizing) == "function" then frame:StartSizing("BOTTOMRIGHT") end end)
  self.resizeGrip:SetScript("OnMouseUp", function() if type(frame.StopMovingOrSizing) == "function" then frame:StopMovingOrSizing(); saveGeometry(self) end end)

  self.title = label(frame, "GameFontHighlightLarge", "TOPLEFT", frame, 14, -12, 300, 22)
  self.close = button(frame, "Close", 70, 22); self.close:SetPoint("TOPRIGHT", -12, -10); self.close:SetScript("OnClick", function() self:Hide() end)
  self.tabs = {}
  local charactersTab = button(frame, "Characters", 100, 24); charactersTab:SetPoint("TOPLEFT", 14, -42)
  local recipesTab = button(frame, "Recipes", 100, 24); recipesTab:SetPoint("LEFT", charactersTab, "RIGHT", 4, 0)
  self.tabs.characters, self.tabs.recipes = charactersTab, recipesTab
  charactersTab:SetScript("OnClick", function() self.tab = "characters"; self:Refresh() end)
  recipesTab:SetScript("OnClick", function() self.tab = "recipes"; self:Refresh() end)
  self.body = CreateFrame("Frame", nil, frame); self.body:SetPoint("TOPLEFT", 10, -72); self.body:SetPoint("BOTTOMRIGHT", -10, 10)
  self.characterScroll = CreateFrame("ScrollFrame", nil, self.body, "UIPanelScrollFrameTemplate")
  self.characterScroll:SetPoint("TOPLEFT", 0, 0); self.characterScroll:SetPoint("BOTTOMRIGHT", 0, 0)
  self.characterContent = CreateFrame("Frame", nil, self.characterScroll); self.characterContent:SetSize(570, 1); self.characterScroll:SetScrollChild(self.characterContent)
  self.recipeControls = CreateFrame("Frame", nil, self.body); self.recipeControls:SetPoint("TOPLEFT", 0, 0); self.recipeControls:SetPoint("TOPRIGHT", 0, 0); self.recipeControls:SetHeight(30)
  self.recipeScroll = CreateFrame("ScrollFrame", nil, self.body, "UIPanelScrollFrameTemplate"); self.recipeScroll:SetPoint("TOPLEFT", 0, -58); self.recipeScroll:SetPoint("BOTTOMRIGHT", 0, 0)
  self.recipeContent = CreateFrame("Frame", nil, self.recipeScroll); self.recipeContent:SetSize(570, 1); self.recipeScroll:SetScrollChild(self.recipeContent)
  self:CreateRecipeControls()
  self.initialized = true
  self:Refresh()
  frame:Hide()
  return self
end

function UI:CreateRecipeControls()
  if not self.recipeControls or self.recipeSearch then return end
  local controls = self.recipeControls
  label(controls, "GameFontNormalSmall", "TOPLEFT", controls, 2, -7, 42, 18):SetText("Search")
  self.recipeSearch = editBox(controls, 122, 22); self.recipeSearch:SetPoint("TOPLEFT", 48, -2)
  label(controls, "GameFontNormalSmall", "TOPLEFT", controls, 176, -7, 34, 18):SetText("Prof")
  self.recipeProfession = editBox(controls, 82, 22); self.recipeProfession:SetPoint("TOPLEFT", 205, -2)
  label(controls, "GameFontNormalSmall", "TOPLEFT", controls, 292, -7, 34, 18):SetText("By")
  self.recipeCharacter = editBox(controls, 82, 22); self.recipeCharacter:SetPoint("TOPLEFT", 315, -2)
  label(controls, "GameFontNormalSmall", "TOPLEFT", controls, 402, -7, 46, 18):SetText("Status")
  self.recipeStatus = editBox(controls, 70, 22); self.recipeStatus:SetPoint("TOPLEFT", 448, -2)
  label(controls, "GameFontNormalSmall", "TOPLEFT", controls, 2, -31, 58, 18):SetText("Transfer")
  self.recipeTransfer = editBox(controls, 170, 22); self.recipeTransfer:SetPoint("TOPLEFT", 62, -26)
  controls:SetHeight(54)
  local function changed() if self.frame and self.frame:IsShown() and self.tab == "recipes" then self:RefreshRecipes() end end
  self.recipeSearch:SetScript("OnTextChanged", changed); self.recipeProfession:SetScript("OnTextChanged", changed)
  self.recipeCharacter:SetScript("OnTextChanged", changed); self.recipeStatus:SetScript("OnTextChanged", changed); self.recipeTransfer:SetScript("OnTextChanged", changed)
end

function UI:Open(productKey)
  if productKey then self.productKey = productKey end
  if not self.initialized then self:Initialize() end
  if self.frame then self.frame:Show(); self:Refresh() end
end

function UI:Show() self:Open() end
function UI:Hide() if self.frame then self.frame:Hide() end end
function UI:Toggle() if self.frame and self.frame:IsShown() then self:Hide() else self:Open() end end

function UI:Refresh()
  if not self.frame then return end
  local productKey, product = getProduct(self)
  self.title:SetText("AltCraft Tracker — " .. text(productKey, "unknown product"))
  self.characterScroll:SetShown(self.tab == "characters"); self.recipeControls:SetShown(self.tab == "recipes"); self.recipeScroll:SetShown(self.tab == "recipes")
  if self.tab == "characters" then self:RefreshCharacters(productKey, product) else self:RefreshRecipes(productKey, product) end
end

function UI:RefreshCharacters(productKey, product)
  hideRows(self.rows); self.rows = {}
  local settings = self.repository and self.repository.db and self.repository.db.settings or {}
  local rows = ACT.ViewModels.BuildCharacters(product, { now = now(self.env), settings = settings, productKey = productKey, expanded = self.expandedCharacters })
  local y, contentHeight = -4, 0
  for _, model in ipairs(rows) do
    local row = CreateFrame("Button", nil, self.characterContent); row:SetPoint("TOPLEFT", 2, y); row:SetSize(550, 26); self.rows[#self.rows + 1] = row
    local arrow = model.expanded and "v" or ">"
    local summary = "[" .. (model.className ~= "" and model.className or "?") .. "] " .. model.name .. "  L" .. tostring(model.level)
    local professions = {}
    for _, profession in ipairs(model.professions) do professions[#professions + 1] = profession.name .. " " .. tostring(profession.rank) end
    if #professions > 0 then summary = summary .. "  " .. table.concat(professions, " | ") end
    summary = summary .. "  seen " .. model.lastSeenLabel .. "  [" .. arrow .. "]"
    local line = label(row, "GameFontNormal", "LEFT", row, 4, 0, 470, 24); line:SetText(summary)
    local hint = label(row, "GameFontDisableSmall", "RIGHT", row, -4, 0, 70, 20); hint:SetText(model.tracked and "tracked" or "untracked")
    row:SetScript("OnClick", function() self.expandedCharacters[model.key] = not self.expandedCharacters[model.key]; self:Refresh() end)
    y = y - 28; contentHeight = contentHeight + 28
    if model.expanded then
      local details = CreateFrame("Frame", nil, self.characterContent); details:SetPoint("TOPLEFT", 16, y); details:SetSize(520, 100); self.rows[#self.rows + 1] = details
      local identity = "Identity: " .. model.name .. (model.realm and " @ " .. text(model.realm) or "") .. " | " .. text(model.faction, "faction unknown")
      label(details, "GameFontHighlightSmall", "TOPLEFT", details, 0, 0, 510, 18):SetText(identity)
      label(details, "GameFontHighlightSmall", "TOPLEFT", details, 0, -18, 510, 18):SetText("Transfer: " .. text(model.transferGroup, "unknown") .. " | last seen: " .. ACT.ViewModels.FormatTimestamp(model.lastSeenAt, self.env))
      local scan = "Bags: " .. model.bagsFreshness.label .. " | Bank: " .. model.bankFreshness.label
      label(details, "GameFontHighlightSmall", "TOPLEFT", details, 0, -36, 510, 18):SetText(scan)
      local py = -56
      for _, profession in ipairs(model.professions) do
        label(details, "GameFontNormalSmall", "TOPLEFT", details, 0, py, 510, 18):SetText(profession.name .. " " .. profession.rank .. "/" .. profession.maxRank .. " — recipes " .. profession.recipeScanState)
        py = py - 16
      end
      local trackCaption = model.tracked and "Untrack" or "Track"
      local track = button(details, trackCaption, 76, 20); track:SetPoint("TOPLEFT", 0, py - 2); track:SetScript("OnClick", function() self:SetTracked(model.key, not model.tracked); self:Refresh() end)
      local forget = button(details, "Forget", 76, 20); forget:SetPoint("LEFT", track, "RIGHT", 5, 0); forget:SetScript("OnClick", function() self:ConfirmForget(productKey, model.key, model.name) end)
      details:SetHeight(math.max(96, -py + 28)); y = y - details:GetHeight() - 4; contentHeight = contentHeight + details:GetHeight() + 4
    end
  end
  self.characterContent:SetHeight(math.max(1, contentHeight + 12))
end

function UI:SetTracked(characterKey, tracked)
  local productKey = getProduct(self)
  if self.characterService and type(self.characterService.SetTracked) == "function" then return self.characterService:SetTracked(tracked, productKey, characterKey) end
  if self.repository and type(self.repository.SetTracked) == "function" then return self.repository:SetTracked(productKey, characterKey, tracked == true) end
  return false
end

function UI:ConfirmForget(productKey, characterKey, displayName)
  local function forget()
    if self.characterService and type(self.characterService.Forget) == "function" then self.characterService:Forget(productKey, characterKey)
    elseif self.repository and type(self.repository.ForgetCharacter) == "function" then self.repository:ForgetCharacter(productKey, characterKey) end
    self.expandedCharacters[characterKey] = nil; self:Refresh()
  end
  if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
    local name = "ALTCRAFTTRACKER_FORGET"
    StaticPopupDialogs[name] = { text = "Forget " .. text(displayName, characterKey) .. " and all snapshots?", button1 = YES or "Yes", button2 = NO or "No", hideOnEscape = true, timeout = 0, whileDead = true, OnAccept = forget }
    StaticPopup_Show(name)
  end
end

function UI:RefreshRecipes(productKey, product)
  hideRows(self.recipeRows); self.recipeRows = {}
  local transferText = self.recipeTransfer and self.recipeTransfer:GetText() or ""
  local query = { productKey = productKey, search = self.recipeSearch and self.recipeSearch:GetText() or "", profession = self.recipeProfession and self.recipeProfession:GetText() or "", knownBy = self.recipeCharacter and self.recipeCharacter:GetText() or "", craftability = self.recipeStatus and self.recipeStatus:GetText() or "", calculate = true }
  local context = self.api and type(self.api.GetCurrentContext) == "function" and self.api:GetCurrentContext() or {}
  query.currentCharacterKey = context and (context.key or context.characterKey)
  query.transferGroup = transferText ~= "" and transferText or (context and context.transferGroup)
  query.transferOnly = transferText ~= ""
  local rows = ACT.ViewModels.BuildRecipes(self.catalog, productKey, query)
  local y, contentHeight = -4, 0
  for _, model in ipairs(rows) do
    local recipe = model.recipe or {}; local expanded = self.expandedRecipes[model.key] == true
    local row = CreateFrame("Button", nil, self.recipeContent); row:SetPoint("TOPLEFT", 2, y); row:SetSize(550, 28); self.recipeRows[#self.recipeRows + 1] = row
    local line = label(row, "GameFontNormal", "LEFT", row, 4, 0, 540, 26); line:SetText((expanded and "v " or "> ") .. text(model.name, "Unknown recipe") .. "  " .. text(model.professionName, "Unknown profession") .. "  Known: " .. text(model.knownLabel, "none") .. "  Transfer: " .. model.transferLabel)
    row:SetScript("OnClick", function() self.expandedRecipes[model.key] = not expanded; self:Refresh() end)
    y = y - 30; contentHeight = contentHeight + 30
    if expanded then
      local calc = model.craftability or ACT.ViewModels.GetRecipeCalculation(self.craftability, recipe, product, query)
      local detail = CreateFrame("Frame", nil, self.recipeContent); detail:SetPoint("TOPLEFT", 16, y); detail:SetSize(520, 40); self.recipeRows[#self.recipeRows + 1] = detail
      local nowSummary = "unavailable (0 crafts)"
      local transferSummary = "unavailable (0 crafts)"
      if calc then
        local nowResult, transferResult = calc.availableNow or {}, calc.afterTransfer or {}
        nowSummary = ACT.ViewModels.FormatAvailability(nowResult)
        transferSummary = ACT.ViewModels.FormatAvailability(transferResult)
      end
      label(detail, "GameFontHighlightSmall", "TOPLEFT", detail, 0, 0, 510, 18):SetText("Known by " .. text(model.knownLabel, "none") .. " | Now: " .. nowSummary .. " | After transfer: " .. transferSummary)
      local materialRows = ACT.ViewModels.BuildMaterialRows(recipe, calc or {}, { now = query.now, itemResolver = function(itemID) if self.env and type(self.env.GetItemInfo) == "function" then return self.env.GetItemInfo(itemID) end end })
      local my = -20
      for _, material in ipairs(materialRows) do
        local materialLine = label(detail, "GameFontNormalSmall", "TOPLEFT", detail, 0, my, 510, 18)
        local nowShortage = material.nowShortage ~= nil and (" short " .. tostring(material.nowShortage)) or ""
        local transferShortage = material.afterTransferShortage ~= nil and (" short " .. tostring(material.afterTransferShortage)) or ""
        materialLine:SetText(text(material.name, "Item " .. tostring(material.itemID)) .. "  need " .. tostring(material.required)
          .. " | now " .. tostring(material.nowOwned or 0) .. " bags, " .. text(material.nowStatus, "unknown") .. nowShortage
          .. " | after transfer " .. tostring(material.afterTransferOwned or 0) .. ", " .. text(material.afterTransferStatus, "unknown") .. transferShortage)
        my = my - 17
        for _, characterRow in ipairs(material.characters or {}) do
          local cell = CreateFrame("Button", nil, detail); cell:SetPoint("TOPLEFT", 18, my); cell:SetSize(492, 16)
          local cellText = label(cell, "GameFontDisableSmall", "LEFT", cell, 0, 0, 492, 16)
          local bags, bagsMeta = ACT.ViewModels.FormatMaterialCell(characterRow, "bags", self.env)
          local bank, bankMeta = ACT.ViewModels.FormatMaterialCell(characterRow, "bank", self.env)
          cellText:SetText("  " .. text(characterRow.displayName, characterRow.characterKey) .. ": " .. bags .. ", " .. bank)
          -- FontStrings do not expose mouse scripts on every Classic build;
          -- attach the exact snapshot text only when the widget supports it.
          if type(cell.SetScript) == "function" then
            cell:SetScript("OnEnter", function() if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(cell, "ANCHOR_RIGHT"); GameTooltip:AddLine(text(characterRow.displayName, characterRow.characterKey)); GameTooltip:AddLine(bagsMeta.tooltip or text(bags)); GameTooltip:AddLine(bankMeta.tooltip or text(bank)); GameTooltip:Show() end end)
            cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
          end
          my = my - 15
        end
      end
      detail:SetHeight(math.max(42, -my)); y = y - detail:GetHeight() - 4; contentHeight = contentHeight + detail:GetHeight() + 4
    end
  end
  self.recipeContent:SetHeight(math.max(1, contentHeight + 12))
end

return UI
