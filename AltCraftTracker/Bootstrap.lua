AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker

function ACT.Now()
  if type(_G.time) == "function" then
    return _G.time()
  end
  if type(_G.GetServerTime) == "function" then
    return _G.GetServerTime()
  end
  return 0
end

function ACT:SetError(message)
  self.Runtime = self.Runtime or {}
  self.Runtime.lastError = tostring(message)
end

function ACT:CaptureContext(event, eventLevel)
  if not self.Api then
    return
  end
  local context = self.Api:GetCurrentContext()
  if eventLevel then
    context.level = tonumber(eventLevel) or context.level
  end
  self.Runtime.context = context
  self.Runtime.lastContextEvent = event
  self.Runtime.lastContextAt = self.Now()
end

local function countMap(value)
  local count = 0
  if type(value) ~= "table" then
    return 0
  end
  for _ in pairs(value) do
    count = count + 1
  end
  return count
end

function ACT:GetDatabaseCounts()
  local tracked, recipes = 0, 0
  local db = self.Repository and type(self.Repository.GetDatabase) == "function"
    and self.Repository:GetDatabase() or _G.AltCraftTrackerDB
  if type(db) ~= "table" or type(db.products) ~= "table" then
    return tracked, recipes
  end
  for _, product in pairs(db.products) do
    if type(product) == "table" then
      recipes = recipes + countMap(product.recipes)
      if type(product.characters) == "table" then
        for _, character in pairs(product.characters) do
          if type(character) == "table" and character.tracked == true then
            tracked = tracked + 1
          end
        end
      end
    end
  end
  return tracked, recipes
end

function ACT:GetStatusLines()
  local context = self.Runtime and self.Runtime.context
  local client = context and context.client or (self.Api and self.Api:GetClientInfo() or {})
  local capabilities = self.Api and self.Api:GetCapabilities() or {}
  local tracked, recipes = self:GetDatabaseCounts()
  local professionAt = self.Runtime and self.Runtime.lastProfessionScanAt
  local bagAt = self.Inventory and self.Inventory.lastResults and self.Inventory.lastResults.bags
    and self.Inventory.lastResults.bags.bagsScannedAt or (self.Runtime and self.Runtime.lastBagScanAt)
  local bankAt = self.Inventory and self.Inventory.lastResults and self.Inventory.lastResults.bank
    and self.Inventory.lastResults.bank.bankScannedAt or (self.Runtime and self.Runtime.lastBankScanAt)
  local lines = {
    "version " .. self.ADDON_VERSION .. ", schema " .. tostring(self.SCHEMA_VERSION),
    "product " .. tostring(client.product) .. ", client " .. tostring(client.version ~= "" and client.version or "unknown")
      .. ", build " .. tostring(client.build ~= "" and client.build or "unknown")
      .. ", interface " .. tostring(client.interface),
    "API adapter " .. tostring(self.product == self.PRODUCT_CLASSIC_ERA and "Classic" or "unsupported") .. ", current key " .. tostring(context and context.key or "unknown"),
    "transfer ecosystem " .. tostring(context and context.transferGroup or "unknown"),
    "last character scan " .. tostring(self.Runtime and self.Runtime.lastContextEvent and (self.Runtime.lastContextEvent .. " at " .. tostring(self.Runtime.lastContextAt or "unknown")) or "not scanned"),
    "last profession scan " .. tostring(professionAt or "not scanned")
      .. "; last bag scan " .. tostring(bagAt or "not scanned")
      .. "; last bank scan " .. tostring(bankAt or "not scanned"),
    "tracked characters " .. tostring(tracked) .. ", cached recipes " .. tostring(recipes),
  }
  local unsupported = {}
  for name, supported in pairs(capabilities) do
    if not supported then
      unsupported[#unsupported + 1] = name
    end
  end
  table.sort(unsupported)
  lines[#lines + 1] = "unsupported capabilities " .. (#unsupported > 0 and table.concat(unsupported, ", ") or "none")
  local repositoryDiagnostics = self.Runtime and self.Runtime.repositoryDiagnostics
  lines[#lines + 1] = "repository " .. (self.Repository and self.Repository:IsReadOnly() and "read-only (newer schema)" or "writable")
    .. "; diagnostics errors " .. tostring(repositoryDiagnostics and #repositoryDiagnostics.errors or 0)
    .. ", quarantined " .. tostring(repositoryDiagnostics and #repositoryDiagnostics.quarantined or 0)
  lines[#lines + 1] = "last scanner error " .. tostring(self.Runtime and self.Runtime.lastError or "none")
  return lines
end

function ACT:Initialize()
  if self.initialized then
    return true
  end
  self.Runtime = { scans = {}, lastError = nil }
  self.Api, self.product = self.ApiCompat.Detect(_G)
  self.Repository = self.Repository:Create(_G)
  self.Repository:Initialize(_G.AltCraftTrackerDB, self.Api)
  self.Runtime.repositoryDiagnostics = self.Repository:GetDiagnostics()
  self.Dispatcher = self.EventDispatcher:Create(_G)
  self.Commands = self.Commands:Create(_G)

  -- Construct the dependency graph in the same order in which snapshots are
  -- consumed. Every constructor is guarded so a missing optional module/API
  -- disables only that feature instead of preventing the addon from loading.
  if self.InventoryScanner and type(self.InventoryScanner.Create) == "function" then
    self.Inventory = self.InventoryScanner:Create(_G, self.Api, self.Repository, {
      onResult = function(result)
        if type(result) == "table" then
          if result.location == "bags" then self.Runtime.lastBagScanAt = result.bagsScannedAt end
          if result.location == "bank" then self.Runtime.lastBankScanAt = result.bankScannedAt end
        end
        if self.UI and type(self.UI.Refresh) == "function" then self.UI:Refresh() end
      end,
    })
    if self.Inventory.Initialize then self.Inventory:Initialize(self.Api, self.Repository) end
  end
  if self.CharacterService and type(self.CharacterService.Create) == "function" then
    self.Characters = self.CharacterService:Create(_G, self.Api, self.Repository, self.Inventory, {})
    self.CharacterServiceInstance = self.Characters
    self.Characters:Initialize(self.Dispatcher, self.Api, self.Repository, self.Inventory)
  end
  if self.ProfessionScanner and type(self.ProfessionScanner.Create) == "function" then
    self.Professions = self.ProfessionScanner:Create(_G, self.Api, self.Repository, {
      contextProvider = function()
        return self.Characters and self.Characters.currentContext or self.Api:GetCurrentContext()
      end,
      onResult = function(result)
        if type(result) == "table" and result.scannedAt then self.Runtime.lastProfessionScanAt = result.scannedAt end
        if self.UI and type(self.UI.Refresh) == "function" then self.UI:Refresh() end
      end,
    })
    self.Professions:Initialize(self.Api, self.Repository)
    if self.Characters and self.Characters.SetProfessionScanner then self.Characters:SetProfessionScanner(self.Professions) end
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_CLOSE", "PLAYER_LOGOUT" }) do
      local eventName = event
      self.Dispatcher:On(eventName, function(...)
        local ok, result = pcall(self.Professions.HandleEvent, self.Professions, eventName, ...)
        if not ok then self:SetError(result); return nil end
        if type(result) == "table" and result.scannedAt then self.Runtime.lastProfessionScanAt = result.scannedAt end
        return result
      end)
    end
  end
  if self.CraftabilityService and type(self.CraftabilityService.Create) == "function" then
    self.Craftability = self.CraftabilityService:Create(self.Repository, { productKey = self.product })
  end
  if self.RecipeCatalog and type(self.RecipeCatalog.Create) == "function" then
    self.Catalog = self.RecipeCatalog:Create(self.Repository, { productKey = self.product, craftabilityService = self.Craftability })
    if self.Catalog.SetCraftabilityService then self.Catalog:SetCraftabilityService(self.Craftability) end
  end
  if self.UI and type(self.UI.Create) == "function" then
    self.UI = self.UI:Create({ env = _G, repository = self.Repository, catalog = self.Catalog,
      craftabilityService = self.Craftability, characterService = self.Characters,
      api = self.Api, productKey = self.product })
    if type(self.UI.Initialize) == "function" then self.UI:Initialize() end
  end
  if self.MinimapButton and type(self.MinimapButton.Create) == "function" then
    self.MinimapButton = self.MinimapButton:Create({ env = _G, repository = self.Repository,
      onClick = function() if self.UI and self.UI.Toggle then self.UI:Toggle() end end })
    if type(self.MinimapButton.Initialize) == "function" then self.MinimapButton:Initialize() end
  end

  -- CharacterService owns inventory lifecycle callbacks. Profession lifecycle
  -- callbacks above are independent, while these handlers are presentation-
  -- only and never trigger a second scanner.
  local function refreshUI()
    if self.UI and type(self.UI.Refresh) == "function" then self.UI:Refresh() end
  end
  for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_CLOSE",
    "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_CLOSED" }) do
    self.Dispatcher:On(event, refreshUI)
  end
  if self.Characters and self.Characters.StartReconciliation then self.Characters:StartReconciliation() end
  self.Dispatcher:On("PLAYER_LOGIN", function()
    self:CaptureContext("PLAYER_LOGIN")
  end)
  self.Dispatcher:On("PLAYER_ENTERING_WORLD", function()
    self:CaptureContext("PLAYER_ENTERING_WORLD")
  end)
  self.Dispatcher:On("PLAYER_LEVEL_UP", function(level)
    self:CaptureContext("PLAYER_LEVEL_UP", level)
  end)
  self.Dispatcher:On("PLAYER_LOGOUT", function()
    self:CaptureContext("PLAYER_LOGOUT")
  end)
  self.Dispatcher:Initialize()
  self.Commands:Initialize()
  self.initialized = true
  return true
end

if type(_G.CreateFrame) == "function" then
  local bootstrap = CreateFrame("Frame", "AltCraftTrackerBootstrap")
  bootstrap:RegisterEvent("ADDON_LOADED")
  bootstrap:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ACT.ADDON_NAME then
      ACT:Initialize()
    end
  end)
end
