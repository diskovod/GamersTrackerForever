GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local UI = {}
UI.__index = UI
GTF.UI = UI

-- Bindings.xml calls this stable global; Task 7 may replace GTF.UI with the
-- configured instance after repository/service initialization.
function GTF_UI_TOGGLE()
  if GTF.UI and type(GTF.UI.Toggle) == "function" then GTF.UI:Toggle() end
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
  if type(GTF.Now) == "function" then return tonumber(GTF.Now()) or 0 end
  return 0
end

local function getProduct(self)
  local key = self.productKey
  if not key and self.api and type(self.api.GetProduct) == "function" then key = self.api:GetProduct() end
  if not key and self.api and type(self.api.GetCurrentContext) == "function" then
    local context = self.api:GetCurrentContext() or {}
    key = context.productKey or context.product
  end
  key = key or GTF.product or GTF.PRODUCT_CLASSIC_ERA
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
  return type(value) == "table" and value or { point = "CENTER", x = 0, y = 0, width = 900, height = 560 }
end

local function saveGeometry(self)
  if not self.frame or type(self.frame.GetPoint) ~= "function" then return end
  local point, _, relative, x, y = self.frame:GetPoint(1)
  local value = { point = point or "CENTER", relative = relative or "CENTER", x = x or 0, y = y or 0,
    width = self.frame.GetWidth and self.frame:GetWidth() or 900, height = self.frame.GetHeight and self.frame:GetHeight() or 560 }
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
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
  end
end

local function resolveItem(self, itemID)
  local env = self.env or _G
  local name, link, icon
  if type(env.GetItemInfo) == "function" then
    local ok, itemName, itemLink, _, _, _, _, _, _, _, itemIcon = pcall(env.GetItemInfo, itemID)
    if ok then name, link, icon = itemName, itemLink, itemIcon end
  end
  if not icon and type(env.GetItemIcon) == "function" then
    local ok, value = pcall(env.GetItemIcon, itemID)
    if ok then icon = value end
  end
  local itemAPI = env.C_Item
  if not icon and type(itemAPI) == "table" and type(itemAPI.GetItemIconByID) == "function" then
    local ok, value = pcall(itemAPI.GetItemIconByID, itemID)
    if ok then icon = value end
  end
  return name, link, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function setIcon(texture, value)
  if texture and type(texture.SetTexture) == "function" then
    texture:SetTexture(value or "Interface\\Icons\\INV_Misc_QuestionMark")
  end
end

local function attachItemTooltip(self, frame, itemID, itemLink, iconInset)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 then return end
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(owner)
    local tooltip = self.env and self.env.GameTooltip or GameTooltip
    if not tooltip or type(tooltip.SetOwner) ~= "function"
      or type(tooltip.SetHyperlink) ~= "function" then return end
    local link = type(itemLink) == "string" and itemLink ~= "" and itemLink
      or "item:" .. tostring(itemID)
    if type(tooltip.SetPoint) == "function" then
      tooltip:SetOwner(owner, "ANCHOR_NONE")
      if type(tooltip.ClearAllPoints) == "function" then tooltip:ClearAllPoints() end
      if iconInset then
        tooltip:SetPoint("TOPLEFT", owner, "TOPLEFT", iconInset, 0)
      else
        tooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
      end
    else
      tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    if ok then
      tooltip:Show()
      local compare = self.env and self.env.GameTooltip_ShowCompareItem or GameTooltip_ShowCompareItem
      if type(compare) == "function" then pcall(compare, tooltip) end
    else
      tooltip:Hide()
    end
  end)
  frame:SetScript("OnLeave", function()
    local tooltip = self.env and self.env.GameTooltip or GameTooltip
    if tooltip and type(tooltip.Hide) == "function" then tooltip:Hide() end
  end)
end

local function hideRows(rows)
  for _, row in ipairs(rows or {}) do if row.Hide then row:Hide() end end
end

function UI:Create(options)
  options = type(options) == "table" and options or {}
  local self = setmetatable({ env = options.env or _G, repository = options.repository, catalog = options.catalog,
    craftability = options.craftabilityService or options.craftability, characterService = options.characterService,
    api = options.api, productKey = options.productKey, getGeometry = options.getGeometry, setGeometry = options.setGeometry,
    professionsSupported = options.professionsSupported ~= false,
    recipesSupported = options.recipesSupported ~= false,
    expandedCharacters = {}, expandedProfessions = {}, expandedRecipes = {}, tab = "characters", rows = {}, recipeRows = {}, initialized = false,
    selectedCharacterKey = options.selectedCharacterKey, selectedProfessionKey = nil, selectedRecipeKey = nil,
    statusMessage = nil }, UI)
  return self
end

function UI:SetDependencies(dependencies)
  dependencies = type(dependencies) == "table" and dependencies or {}
  for _, key in ipairs({ "repository", "catalog", "craftability", "craftabilityService", "characterService", "api", "productKey", "getGeometry", "setGeometry", "professionsSupported", "recipesSupported" }) do
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
  local ok, value = pcall(CreateFrame, "Frame", "GamersTrackerForeverFrame", UIParent, "BackdropTemplate")
  frame = ok and value or CreateFrame("Frame", "GamersTrackerForeverFrame", UIParent)
  self.frame = frame
  frame:SetSize(900, 560)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetResizable(true)
  if type(frame.SetResizeBounds) == "function" then frame:SetResizeBounds(760, 400, 1100, 800)
  elseif type(frame.SetMinResize) == "function" then frame:SetMinResize(760, 400) end
  createBackdrop(frame)
  local saved = geometry(self)
  frame:ClearAllPoints()
  frame:SetPoint(saved.point or "CENTER", UIParent, saved.relative or "CENTER", tonumber(saved.x) or 0, tonumber(saved.y) or 0)
  frame:SetSize(math.max(760, tonumber(saved.width) or 900), math.max(400, tonumber(saved.height) or 560))
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
  frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); saveGeometry(self) end)
  frame:SetScript("OnMouseUp", function(f, mouseButton) if mouseButton == "LeftButton" and f.isMoving then f:StopMovingOrSizing(); saveGeometry(self) end end)
  self.resizeGrip = CreateFrame("Button", nil, frame)
  self.resizeGrip:SetSize(16, 16); self.resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
  self.resizeGrip:SetScript("OnMouseDown", function(f, mouseButton) if mouseButton == "LeftButton" and type(frame.StartSizing) == "function" then frame:StartSizing("BOTTOMRIGHT") end end)
  self.resizeGrip:SetScript("OnMouseUp", function() if type(frame.StopMovingOrSizing) == "function" then frame:StopMovingOrSizing(); saveGeometry(self) end end)

  self.title = label(frame, "GameFontHighlightLarge", "TOPLEFT", frame, 14, -12, 360, 22)
  self.trackedHeader = label(frame, "GameFontNormal", "TOPLEFT", frame, 380, -15, 170, 20)
  self.close = button(frame, "Close", 70, 22); self.close:SetPoint("TOPRIGHT", -12, -10); self.close:SetScript("OnClick", function() self:Hide() end)
  self.tabs = {}
  local charactersTab = button(frame, "Characters", 100, 24); charactersTab:SetPoint("TOPLEFT", 14, -42)
  local recipesTab = button(frame, "Recipes", 100, 24); recipesTab:SetPoint("LEFT", charactersTab, "RIGHT", 4, 0)
  self.tabs.characters, self.tabs.recipes = charactersTab, recipesTab
  if not self.recipesSupported then
    recipesTab:Hide()
  end
  charactersTab:SetScript("OnClick", function() self.tab = "characters"; self:Refresh() end)
  recipesTab:SetScript("OnClick", function() self.tab = "recipes"; self:Refresh() end)
  self.body = CreateFrame("Frame", nil, frame); self.body:SetPoint("TOPLEFT", 10, -72); self.body:SetPoint("BOTTOMRIGHT", -10, 10)
  self.leftPane = CreateFrame("Frame", nil, self.body); self.leftPane:SetPoint("TOPLEFT", 0, 0); self.leftPane:SetPoint("BOTTOMLEFT", 0, 0); self.leftPane:SetWidth(250)
  self.leftTitle = label(self.leftPane, "GameFontNormal", "TOPLEFT", self.leftPane, 6, -4, 225, 20); self.leftTitle:SetText("Characters · Professions")
  self.trackLimitLabel = label(self.leftPane, "GameFontNormalSmall", "TOPLEFT", self.leftPane, 6, -27, 82, 20); self.trackLimitLabel:SetText("Track up to")
  self.trackLimitDropdown = CreateFrame("Frame", "GamersTrackerForeverTrackLimit", self.leftPane, "UIDropDownMenuTemplate")
  self.trackLimitDropdown:SetPoint("TOPLEFT", 82, -20)
  -- Classic/SoD use the frame-first UIDropDownMenu signatures.
  if type(UIDropDownMenu_SetWidth) == "function" then UIDropDownMenu_SetWidth(self.trackLimitDropdown, 92) end
  self.characterScroll = CreateFrame("ScrollFrame", nil, self.leftPane, "UIPanelScrollFrameTemplate")
  self.characterScroll:SetPoint("TOPLEFT", 2, -54); self.characterScroll:SetPoint("BOTTOMRIGHT", -16, 0)
  self.characterContent = CreateFrame("Frame", nil, self.characterScroll); self.characterContent:SetSize(228, 1); self.characterScroll:SetScrollChild(self.characterContent)
  self.rightPane = CreateFrame("Frame", nil, self.body); self.rightPane:SetPoint("TOPLEFT", self.leftPane, "TOPRIGHT", 8, 0); self.rightPane:SetPoint("BOTTOMRIGHT", 0, 0)
  self.detailScroll = CreateFrame("ScrollFrame", nil, self.rightPane, "UIPanelScrollFrameTemplate"); self.detailScroll:SetPoint("TOPLEFT", 2, 0); self.detailScroll:SetPoint("BOTTOMRIGHT", -16, 0)
  self.detailContent = CreateFrame("Frame", nil, self.detailScroll); self.detailContent:SetSize(500, 1); self.detailScroll:SetScrollChild(self.detailContent)
  self.recipeControls = CreateFrame("Frame", nil, self.rightPane)
  -- Keep the filter row inside the right pane even at the 760px minimum.
  -- Its controls end at x≈520, so a fixed 520px canvas avoids the scrollbar
  -- inset shrinking the row to ~504px and clipping the status field.
  self.recipeControls:SetPoint("TOPLEFT", 2, 0); self.recipeControls:SetWidth(520); self.recipeControls:SetHeight(58)
  self.recipeScroll = CreateFrame("ScrollFrame", nil, self.rightPane, "UIPanelScrollFrameTemplate"); self.recipeScroll:SetPoint("TOPLEFT", 2, -58); self.recipeScroll:SetPoint("BOTTOMRIGHT", -16, 0)
  self.recipeContent = CreateFrame("Frame", nil, self.recipeScroll); self.recipeContent:SetSize(500, 1); self.recipeScroll:SetScrollChild(self.recipeContent)
  self:CreateRecipeControls()
  self:CreateTrackLimitDropdown()
  self.initialized = true
  self:Refresh()
  frame:Hide()
  return self
end

function UI:CreateTrackLimitDropdown()
  if not self.trackLimitDropdown or self.trackLimitReady then return end
  local db = self.repository and self.repository.db
  local current = db and db.settings and tonumber(db.settings.maxTrackedCharacters) or 3
  current = math.max(1, math.min(10, math.floor(current)))
  self.trackLimitCurrent = current
  if type(UIDropDownMenu_Initialize) == "function" then
    UIDropDownMenu_Initialize(self.trackLimitDropdown, function(_, level)
      for value = 1, 10 do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value, info.checked = tostring(value), value, value == (self.trackLimitCurrent or current)
        info.func = function() self:SetMaxTrackedCharacters(value) end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    if type(UIDropDownMenu_SetText) == "function" then UIDropDownMenu_SetText(self.trackLimitDropdown, tostring(current)) end
  else
    self.trackLimitButton = button(self.leftPane, tostring(current), 60, 20)
    self.trackLimitButton:SetPoint("TOPLEFT", 92, -22)
    self.trackLimitButton:SetScript("OnClick", function()
      local nextValue = (self.trackLimitCurrent or current) + 1; if nextValue > 10 then nextValue = 1 end
      self:SetMaxTrackedCharacters(nextValue)
    end)
  end
  self.trackLimitReady = true
end

function UI:SetMaxTrackedCharacters(value)
  local ok, result = false, nil
  if self.repository and type(self.repository.SetMaxTrackedCharacters) == "function" then ok, result = self.repository:SetMaxTrackedCharacters(value) end
  if ok then
    self.trackLimitCurrent = result
    if type(UIDropDownMenu_SetText) == "function" then UIDropDownMenu_SetText(self.trackLimitDropdown, tostring(result)) end
    if self.trackLimitButton then self.trackLimitButton:SetText(tostring(result)) end
    self:Refresh()
  else
    self.statusMessage = result or "Unable to change tracking limit"
    if self.frame then self:Refresh() end
  end
  return ok, result
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
  local function changed()
    if self.frame and self.frame:IsShown() and self.tab == "recipes" then
      self:RefreshRecipes(getProduct(self))
    end
  end
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
  if not self.recipesSupported and self.tab == "recipes" then self.tab = "characters" end
  local productKey, product = getProduct(self)
  self.title:SetText("GamersTrackerForever — " .. text(productKey, "unknown product"))
  self.characterScroll:Show()
  self.detailScroll:SetShown(self.tab == "characters"); self.recipeControls:SetShown(self.recipesSupported and self.tab == "recipes"); self.recipeScroll:SetShown(self.recipesSupported and self.tab == "recipes")
  self:RefreshCharacters(productKey, product)
  if self.tab == "recipes" then self:RefreshRecipes(productKey, product) end
end

function UI:RefreshCharacters(productKey, product)
  hideRows(self.rows); self.rows = {}
  local settings = self.repository and self.repository.db and self.repository.db.settings or {}
  local selected = self.selectedCharacterKey or (self.repository and self.repository.GetSelectedCharacterKey and self.repository:GetSelectedCharacterKey()) or settings.selectedCharacterKey
  local pane = GTF.ViewModels.BuildCharacterSelector(product, { now = now(self.env), settings = settings, productKey = productKey, selectedCharacterKey = selected })
  local selectionExists = false
  for _, row in ipairs(pane.characters or {}) do
    if selected ~= nil and tostring(row.key) == tostring(selected) then selectionExists = true; break end
  end
  if not selectionExists and pane.characters[1] then selected = pane.characters[1].key end
  if tostring(self.selectedCharacterKey or "") ~= tostring(selected or "") then
    self.selectedProfessionKey, self.selectedRecipeKey = nil, nil
  end
  self.selectedCharacterKey = selected
  if self.repository and self.repository.SetSelectedCharacterKey then self.repository:SetSelectedCharacterKey(selected) end
  self.trackedHeader:SetText(pane.header)
  if self.trackLimitLabel then self.trackLimitLabel:SetText("Track up to") end
  local y, contentHeight = -4, 0
  local function addTreeRow(caption, indent, height, onClick, font)
    height = height or 24
    local width = math.max(1, 225 - indent)
    if onClick then
      local row = CreateFrame("Button", nil, self.characterContent)
      row:SetPoint("TOPLEFT", 2 + indent, y); row:SetSize(width, height)
      local line = label(row, font or "GameFontNormalSmall", "LEFT", row, 3, 0, width - 4, height)
      line:SetText(caption)
      row:SetScript("OnClick", onClick)
      self.rows[#self.rows + 1] = row
      y = y - height - 2; contentHeight = contentHeight + height + 2
      return row
    else
      local line = label(self.characterContent, font or "GameFontDisableSmall", "TOPLEFT", self.characterContent,
        5 + indent, y, width - 4, height)
      line:SetText(caption)
      self.rows[#self.rows + 1] = line
    end
    y = y - height - 2; contentHeight = contentHeight + height + 2
  end
  for _, model in ipairs(pane.characters) do
    local isSelected = tostring(model.key) == tostring(selected)
    local marker = isSelected and "v " or "> "
    local state = model.tracked and "tracked" or "available"
    addTreeRow(marker .. model.name .. " L" .. tostring(model.level) .. " [" .. state .. "]", 0, 28,
      function() self:SelectCharacter(model.key) end)
    if isSelected then
      if not self.professionsSupported then
        addTreeRow("Professions unavailable", 14)
      elseif #(model.professions or {}) == 0 then
        addTreeRow("No professions captured yet", 14)
      else
        for _, profession in ipairs(model.professions) do
          local treeKey = tostring(model.key) .. "|" .. tostring(profession.key)
          local expanded = self.expandedProfessions[treeKey] == true
          addTreeRow((expanded and "v " or "> ") .. profession.name .. " " .. tostring(profession.rank)
            .. "/" .. tostring(profession.maxRank), 12, 25,
            function() self:ToggleProfession(model.key, profession.key) end)
          if expanded then
            if not self.recipesSupported then
              addTreeRow("Recipes pending", 27)
            elseif #(profession.recipes or {}) == 0 then
              addTreeRow("No recipes captured yet", 27)
            else
              for _, recipe in ipairs(profession.recipes) do
                local selectedRecipe = tostring(self.selectedRecipeKey or "") == tostring(recipe.key)
                local recipeRow = addTreeRow((selectedRecipe and "• " or "  ") .. recipe.name, 27, 24,
                  function() self:SelectRecipe(model.key, profession.key, recipe.key) end)
                local definition = product.recipes and product.recipes[recipe.key]
                attachItemTooltip(self, recipeRow, definition and definition.outputItemID,
                  definition and definition.outputItemLink)
              end
            end
          end
        end
      end
    end
  end
  if #pane.characters == 0 then
    local empty = label(self.characterContent, "GameFontDisableSmall", "TOPLEFT", self.characterContent, 6, -6, 180, 36)
    empty:SetText(pane.emptyLabel or "No characters discovered yet. Log in with a character to begin tracking.")
    self.rows[#self.rows + 1] = empty
    contentHeight = 42
  end
  self.characterContent:SetHeight(math.max(1, contentHeight + 8))
  self:RefreshDetail(productKey, product, selected)
end

function UI:SelectCharacter(characterKey)
  self.selectedProfessionKey, self.selectedRecipeKey = nil, nil
  self.selectedCharacterKey = characterKey
  if self.repository and type(self.repository.SetSelectedCharacterKey) == "function" then self.repository:SetSelectedCharacterKey(characterKey) end
  self:Refresh()
end

function UI:ToggleProfession(characterKey, professionKey)
  self.selectedCharacterKey = characterKey
  local treeKey = tostring(characterKey) .. "|" .. tostring(professionKey)
  self.expandedProfessions[treeKey] = not self.expandedProfessions[treeKey]
  self.selectedProfessionKey, self.selectedRecipeKey = professionKey, nil
  self.tab = "characters"
  self:Refresh()
end

function UI:SelectRecipe(characterKey, professionKey, recipeKey)
  self.selectedCharacterKey, self.selectedProfessionKey, self.selectedRecipeKey = characterKey, professionKey, recipeKey
  self.expandedProfessions[tostring(characterKey) .. "|" .. tostring(professionKey)] = true
  self.tab = "characters"
  self:Refresh()
end

function UI:RenderRecipeDetail(product, character, profession, recipeRow, y, width, settings)
  local recipe = product.recipes and product.recipes[recipeRow.key]
  local outputButton = CreateFrame("Button", nil, self.detailContent)
  outputButton:SetSize(38, 38); outputButton:SetPoint("TOPLEFT", self.detailContent, 8, y)
  local icon = outputButton:CreateTexture(nil, "ARTWORK")
  icon:SetSize(38, 38); icon:SetPoint("CENTER", outputButton, "CENTER", 0, 0)
  setIcon(icon, recipe and recipe.icon or recipeRow.icon)
  attachItemTooltip(self, outputButton, recipe and recipe.outputItemID, recipe and recipe.outputItemLink)
  self.outputItemButton = outputButton
  self.detailRows[#self.detailRows + 1] = outputButton
  local title = label(self.detailContent, "GameFontHighlightLarge", "TOPLEFT", self.detailContent, 52, y,
    width - 58, 22)
  title:SetText(recipeRow.name); self.detailRows[#self.detailRows + 1] = title
  local subtitle = label(self.detailContent, "GameFontNormalSmall", "TOPLEFT", self.detailContent, 52, y - 23,
    width - 58, 18)
  subtitle:SetText(profession.name .. " " .. tostring(profession.rank) .. "/" .. tostring(profession.maxRank))
  self.detailRows[#self.detailRows + 1] = subtitle
  y = y - 50
  if type(recipe) ~= "table" then
    local missing = label(self.detailContent, "GameFontDisableSmall", "TOPLEFT", self.detailContent, 8, y, width - 16, 30)
    missing:SetText("Recipe details have not been captured yet.")
    self.detailRows[#self.detailRows + 1] = missing
    return y - 40
  end
  local calcOptions = { currentCharacterKey = character.key, transferGroup = character.transferGroup,
    now = now(self.env), settings = settings }
  local calc = GTF.ViewModels.GetRecipeCalculation(self.craftability, recipe, product, calcOptions)
  local summary = label(self.detailContent, "GameFontNormalSmall", "TOPLEFT", self.detailContent, 8, y, width - 16, 20)
  summary:SetText("Now: " .. GTF.ViewModels.FormatAvailability(calc and calc.availableNow)
    .. "  |  After transfer: " .. GTF.ViewModels.FormatAvailability(calc and calc.afterTransfer))
  self.detailRows[#self.detailRows + 1] = summary
  y = y - 28
  local materialTitle = label(self.detailContent, "GameFontHighlight", "TOPLEFT", self.detailContent, 8, y, width - 16, 20)
  materialTitle:SetText("Materials needed")
  self.detailRows[#self.detailRows + 1] = materialTitle
  y = y - 24
  if not calc then
    calc = { reagents = {} }
    for _, reagent in ipairs(recipe.reagents or {}) do
      calc.reagents[#calc.reagents + 1] = { itemID = reagent.itemID, quantity = reagent.quantity,
        kind = reagent.kind, status = "unknown" }
    end
  end
  local materialRows = GTF.ViewModels.BuildMaterialRows(recipe, calc, {
    itemResolver = function(itemID) return resolveItem(self, itemID) end,
  })
  self.materialCards = {}
  if #materialRows == 0 then
    local empty = label(self.detailContent, "GameFontDisableSmall", "TOPLEFT", self.detailContent, 8, y, width - 16, 24)
    empty:SetText(type(recipe.reagents) == "table" and "No materials required." or "Material details are unavailable.")
    self.detailRows[#self.detailRows + 1] = empty
    return y - 30
  end
  local columns = width >= 480 and 2 or 1
  local cardWidth = columns == 2 and math.floor((width - 24) / 2) or width - 16
  for index, material in ipairs(materialRows) do
    local column = (index - 1) % columns
    local rowIndex = math.floor((index - 1) / columns)
    local card = CreateFrame("Frame", nil, self.detailContent)
    card:SetPoint("TOPLEFT", self.detailContent, 8 + column * (cardWidth + 8), y - rowIndex * 55)
    card:SetSize(cardWidth, 50)
    attachItemTooltip(self, card, material.itemID, material.link, 38)
    local materialIcon = card:CreateTexture(nil, "ARTWORK")
    materialIcon:SetSize(32, 32); materialIcon:SetPoint("TOPLEFT", card, 2, -5)
    setIcon(materialIcon, material.icon)
    local name = label(card, "GameFontNormalSmall", "TOPLEFT", card, 40, -3, cardWidth - 42, 20)
    name:SetText(material.name)
    local count = label(card, "GameFontHighlightSmall", "TOPLEFT", card, 40, -23, cardWidth - 42, 20)
    count:SetText(tostring(material.nowOwned or 0) .. "/" .. tostring(material.required) .. " in bags · "
      .. text(material.nowStatus, "unknown"))
    self.detailRows[#self.detailRows + 1] = card
    self.materialCards[#self.materialCards + 1] = card
  end
  y = y - math.ceil(#materialRows / columns) * 55 - 10
  local ok, panel = pcall(CreateFrame, "Frame", nil, self.detailContent, "BackdropTemplate")
  panel = ok and panel or CreateFrame("Frame", nil, self.detailContent)
  panel:SetPoint("TOPLEFT", self.detailContent, 8, y); panel:SetWidth(width - 16)
  createBackdrop(panel)
  self.detailRows[#self.detailRows + 1] = panel
  self.sourceRows = {}
  local py = -10
  local heading = label(panel, "GameFontHighlight", "TOPLEFT", panel, 10, py, width - 36, 20)
  heading:SetText("Who has the materials")
  py = py - 26
  for _, material in ipairs(materialRows) do
    local materialHeading = label(panel, "GameFontNormalSmall", "TOPLEFT", panel, 10, py, width - 36, 18)
    materialHeading:SetText(material.name .. " · need " .. tostring(material.required))
    py = py - 19
    if #(material.characters or {}) == 0 then
      local unavailable = label(panel, "GameFontDisableSmall", "TOPLEFT", panel, 20, py, width - 46, 17)
      unavailable:SetText("Character holdings unavailable")
      py = py - 19
    else
      for _, characterRow in ipairs(material.characters) do
        local row = CreateFrame("Button", nil, panel)
        row:SetPoint("TOPLEFT", panel, 20, py); row:SetSize(width - 46, 18)
        local bags, bagsMeta = GTF.ViewModels.FormatMaterialCell(characterRow, "bags", self.env)
        local bank, bankMeta = GTF.ViewModels.FormatMaterialCell(characterRow, "bank", self.env)
        local caption = label(row, "GameFontDisableSmall", "LEFT", row, 0, 0, width - 46, 18)
        caption:SetText(text(characterRow.displayName, characterRow.characterKey) .. ": " .. bags .. ", " .. bank
          .. (characterRow.included and "" or " · not pooled"))
        row:SetScript("OnEnter", function()
          if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text(characterRow.displayName, characterRow.characterKey))
            GameTooltip:AddLine(bagsMeta.tooltip or text(bags))
            GameTooltip:AddLine(bankMeta.tooltip or text(bank))
            GameTooltip:Show()
          end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        self.sourceRows[#self.sourceRows + 1] = row
        py = py - 19
      end
    end
    py = py - 7
  end
  panel:SetHeight(math.max(54, -py + 8))
  return y - panel:GetHeight() - 10
end

function UI:RefreshDetail(productKey, product, characterKey)
  hideRows(self.detailRows); self.detailRows = {}; self.materialCards = {}; self.sourceRows = {}; self.outputItemButton = nil
  local settings = self.repository and self.repository.db and self.repository.db.settings or {}
  local model = GTF.ViewModels.BuildCharacterDetail(product, characterKey, {
    now = now(self.env), settings = settings, includeInventoryRows = false,
  })
  local width = 500
  if self.rightPane and type(self.rightPane.GetWidth) == "function" then
    local available = tonumber(self.rightPane:GetWidth()) or 0
    if available > 200 then width = math.max(350, available - 24) end
  end
  self.detailContent:SetWidth(width)
  local y = -6
  local function add(caption, font)
    local fs = label(self.detailContent, font or "GameFontNormal", "TOPLEFT", self.detailContent, 8, y,
      width - 16, 20)
    fs:SetText(caption); self.detailRows[#self.detailRows + 1] = fs; y = y - 23
  end
  if model.empty then
    add(model.title or "No character selected", "GameFontHighlight")
    add(model.message or "Select a character from the list.", "GameFontNormalSmall")
    self.detailContent:SetHeight(80)
    return
  end
  local classLabel = model.className and model.className ~= "" and (" " .. model.className) or ""
  add(model.name .. " — level " .. tostring(model.level) .. classLabel, "GameFontHighlightLarge")
  add(text(model.realm, "Realm unknown") .. " | " .. text(model.faction, "Faction unknown") .. " | "
    .. (model.tracked and "tracked" or "not tracked"))
  add("Last seen: " .. GTF.ViewModels.FormatTimestamp(model.lastSeenAt, self.env) .. " | Bags: "
    .. model.bagsFreshness.label .. " | Bank: " .. model.bankFreshness.label, "GameFontNormalSmall")
  local track = button(self.detailContent, model.tracked and "Untrack" or "Track", 86, 22)
  track:SetPoint("TOPLEFT", 8, y - 2)
  track:SetScript("OnClick", function()
    local ok, err = self:SetTracked(model.key, not model.tracked)
    self.statusMessage = ok and nil or err
    self:Refresh()
  end)
  self.detailRows[#self.detailRows + 1] = track
  local forget = button(self.detailContent, "Forget", 70, 22)
  forget:SetPoint("LEFT", track, "RIGHT", 5, 0)
  forget:SetScript("OnClick", function() self:ConfirmForget(productKey, model.key, model.name) end)
  self.detailRows[#self.detailRows + 1] = forget
  y = y - 35
  local selectedProfession, selectedRecipe
  for _, profession in ipairs(model.professions or {}) do
    if tostring(profession.key) == tostring(self.selectedProfessionKey) then
      selectedProfession = profession
      for _, recipe in ipairs(profession.recipes or {}) do
        if tostring(recipe.key) == tostring(self.selectedRecipeKey) then selectedRecipe = recipe; break end
      end
      break
    end
  end
  if self.selectedRecipeKey and not selectedRecipe then self.selectedRecipeKey = nil end
  if selectedRecipe then
    y = self:RenderRecipeDetail(product, model, selectedProfession, selectedRecipe, y, width, settings)
  elseif selectedProfession then
    add(selectedProfession.name .. " " .. tostring(selectedProfession.rank) .. "/"
      .. tostring(selectedProfession.maxRank), "GameFontHighlight")
    if not self.recipesSupported then
      add("Forever beta recipe capture is pending API validation.", "GameFontNormalSmall")
    elseif #(selectedProfession.recipes or {}) == 0 then
      add("No recipes captured yet. Open this profession in game to scan it.", "GameFontDisableSmall")
    else
      add("Choose a recipe under this profession on the left.", "GameFontNormalSmall")
    end
  else
    add("Select a profession on the left to browse its recipes.", "GameFontNormalSmall")
    add("Bag snapshots are saved and shown when a recipe needs their materials.", "GameFontDisableSmall")
  end
  if self.statusMessage then add(self.statusMessage, "GameFontHighlight") end
  self.detailContent:SetHeight(math.max(120, -y + 20))
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
    self.expandedCharacters[characterKey] = nil
    local prefix = tostring(characterKey) .. "|"
    for key in pairs(self.expandedProfessions) do
      if key:sub(1, #prefix) == prefix then self.expandedProfessions[key] = nil end
    end
    if tostring(self.selectedCharacterKey or "") == tostring(characterKey) then
      self.selectedCharacterKey, self.selectedProfessionKey, self.selectedRecipeKey = nil, nil, nil
    end
    self:Refresh()
  end
  if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
    local name = "GAMERSTRACKERFOREVER_FORGET"
    StaticPopupDialogs[name] = { text = "Forget " .. text(displayName, characterKey) .. " and all snapshots?", button1 = YES or "Yes", button2 = NO or "No", hideOnEscape = true, timeout = 0, whileDead = true, OnAccept = forget }
    StaticPopup_Show(name)
  end
end

function UI:RefreshRecipes(productKey, product)
  if not product then productKey, product = getProduct(self) end
  hideRows(self.recipeRows); self.recipeRows = {}
  local recipeWidth = 500
  if self.rightPane and type(self.rightPane.GetWidth) == "function" then
    local available = tonumber(self.rightPane:GetWidth()) or 0
    if available > 100 then recipeWidth = math.max(500, available - 22) end
  end
  if self.recipeContent and type(self.recipeContent.SetWidth) == "function" then self.recipeContent:SetWidth(recipeWidth) end
  local transferText = self.recipeTransfer and self.recipeTransfer:GetText() or ""
  local settings = self.repository and self.repository.db and self.repository.db.settings or {}
  local query = { productKey = productKey, search = self.recipeSearch and self.recipeSearch:GetText() or "", profession = self.recipeProfession and self.recipeProfession:GetText() or "", knownBy = self.recipeCharacter and self.recipeCharacter:GetText() or "", craftability = self.recipeStatus and self.recipeStatus:GetText() or "", calculate = true, now = now(self.env), settings = settings }
  local context = self.api and type(self.api.GetCurrentContext) == "function" and self.api:GetCurrentContext() or {}
  query.currentCharacterKey = self.selectedCharacterKey or (context and (context.key or context.characterKey))
  local selected = query.currentCharacterKey and product.characters and (product.characters[query.currentCharacterKey] or product.characters[tostring(query.currentCharacterKey)])
  local selectedIdentity = selected and selected.identity or {}
  query.transferGroup = transferText ~= "" and transferText or selectedIdentity.transferGroup or (context and context.transferGroup)
  query.transferOnly = transferText ~= ""
  local rows = GTF.ViewModels.BuildRecipes(self.catalog, productKey, query)
  local y, contentHeight = -4, 0
  for _, model in ipairs(rows) do
    local recipe = model.recipe or {}; local expanded = self.expandedRecipes[model.key] == true
    local row = CreateFrame("Button", nil, self.recipeContent); row:SetPoint("TOPLEFT", 2, y); row:SetSize(recipeWidth, 28); self.recipeRows[#self.recipeRows + 1] = row
    local line = label(row, "GameFontNormal", "LEFT", row, 4, 0, math.max(1, recipeWidth - 10), 26); line:SetText((expanded and "v " or "> ") .. text(model.name, "Unknown recipe") .. "  " .. text(model.professionName, "Unknown profession") .. "  Known: " .. text(model.knownLabel, "none") .. "  Transfer: " .. model.transferLabel)
    row:SetScript("OnClick", function() self.expandedRecipes[model.key] = not expanded; self:Refresh() end)
    y = y - 30; contentHeight = contentHeight + 30
    if expanded then
      local calc = model.craftability or GTF.ViewModels.GetRecipeCalculation(self.craftability, recipe, product, query)
      local detailWidth = math.max(450, recipeWidth - 30)
      local detail = CreateFrame("Frame", nil, self.recipeContent); detail:SetPoint("TOPLEFT", 16, y); detail:SetSize(detailWidth, 40); self.recipeRows[#self.recipeRows + 1] = detail
      local nowSummary = "unavailable (0 crafts)"
      local transferSummary = "unavailable (0 crafts)"
      if calc then
        local nowResult, transferResult = calc.availableNow or {}, calc.afterTransfer or {}
        nowSummary = GTF.ViewModels.FormatAvailability(nowResult)
        transferSummary = GTF.ViewModels.FormatAvailability(transferResult)
      end
      label(detail, "GameFontHighlightSmall", "TOPLEFT", detail, 0, 0, math.max(1, detailWidth - 10), 18):SetText("Known by " .. text(model.knownLabel, "none") .. " | Now: " .. nowSummary .. " | After transfer: " .. transferSummary)
      local materialRows = GTF.ViewModels.BuildMaterialRows(recipe, calc or {}, { now = query.now, itemResolver = function(itemID) if self.env and type(self.env.GetItemInfo) == "function" then return self.env.GetItemInfo(itemID) end end })
      local my = -20
      for _, material in ipairs(materialRows) do
        local materialLine = label(detail, "GameFontNormalSmall", "TOPLEFT", detail, 0, my, math.max(1, detailWidth - 10), 18)
        local nowShortage = material.nowShortage ~= nil and (" short " .. tostring(material.nowShortage)) or ""
        local transferShortage = material.afterTransferShortage ~= nil and (" short " .. tostring(material.afterTransferShortage)) or ""
        materialLine:SetText(text(material.name, "Item " .. tostring(material.itemID)) .. "  need " .. tostring(material.required)
          .. " | now " .. tostring(material.nowOwned or 0) .. " bags, " .. text(material.nowStatus, "unknown") .. nowShortage
          .. " | after transfer " .. tostring(material.afterTransferOwned or 0) .. ", " .. text(material.afterTransferStatus, "unknown") .. transferShortage)
        my = my - 17
        for _, characterRow in ipairs(material.characters or {}) do
          local cellWidth = math.max(1, detailWidth - 28)
          local cell = CreateFrame("Button", nil, detail); cell:SetPoint("TOPLEFT", 18, my); cell:SetSize(cellWidth, 16)
          local cellText = label(cell, "GameFontDisableSmall", "LEFT", cell, 0, 0, cellWidth, 16)
          local bags, bagsMeta = GTF.ViewModels.FormatMaterialCell(characterRow, "bags", self.env)
          local bank, bankMeta = GTF.ViewModels.FormatMaterialCell(characterRow, "bank", self.env)
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
