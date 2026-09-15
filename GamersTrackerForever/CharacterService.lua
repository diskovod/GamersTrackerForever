GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local CharacterService = {}
CharacterService.__index = CharacterService
GTF.CharacterService = CharacterService

local function timestamp(env, clock)
  if type(clock) == "function" then return tonumber(clock()) or 0 end
  if env and type(env.time) == "function" then return tonumber(env.time()) or 0 end
  if env and type(env.GetServerTime) == "function" then return tonumber(env.GetServerTime()) or 0 end
  if type(GTF.Now) == "function" then return tonumber(GTF.Now()) or 0 end
  return 0
end

local function currentContext(self, eventLevel)
  if not self.api or type(self.api.GetCurrentContext) ~= "function" then
    return nil, "current character API unavailable"
  end
  local context = self.api:GetCurrentContext()
  if type(context) ~= "table" or not (context.key or context.characterKey) then
    return nil, "current character context unavailable"
  end
  if eventLevel ~= nil then
    context.level = tonumber(eventLevel) or context.level
  end
  context.productKey = context.productKey or context.product or (context.client and (context.client.product or context.client.productKey))
  context.characterKey = context.characterKey or context.key
  if context.identity and not context.identity.transferGroup then
    context.identity.transferGroup = context.transferGroup
  end
  return context
end

function CharacterService:Create(env, api, repository, inventoryScanner, options)
  -- Keep fixture construction ergonomic while retaining the addon form:
  -- (env, api, repository, inventoryScanner, options).
  if env and type(env.GetCurrentContext) == "function" and api and type(api.CommitCharacterContext) == "function" then
    options, inventoryScanner, repository, api, env = inventoryScanner, repository, api, env, _G
  elseif type(env) == "table" and (env.api or env.repository or env.inventory) and api == nil then
    options, api, repository, inventoryScanner, env = env, env.api, env.repository, env.inventory, env.env or _G
  end
  options = options or {}
  local service = setmetatable({
    env = env or _G,
    api = api,
    repository = repository,
    inventory = inventoryScanner,
    clock = options.clock,
    reconcileSeconds = tonumber(options.reconcileSeconds) or 600,
    currentProductKey = nil,
    currentCharacterKey = nil,
    currentContext = nil,
    dispatcher = nil,
    professionScanner = nil,
    ticker = nil,
    lastError = nil,
    lastLoginScanAt = nil,
    lastLogoutScanAt = nil,
  }, CharacterService)
  return service
end

function CharacterService:Initialize(dispatcher, api, repository, inventoryScanner)
  if dispatcher and type(dispatcher.On) == "function" then
    self.dispatcher = dispatcher
  elseif dispatcher and type(dispatcher.GetCurrentContext) == "function" then
    self.api = dispatcher
  end
  if api then self.api = api end
  if repository then self.repository = repository end
  if inventoryScanner then self.inventory = inventoryScanner end
  if self.dispatcher then
    local events = {
      "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED",
      "BAG_UPDATE", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_CLOSED", "PLAYER_LOGOUT",
    }
    for _, event in ipairs(events) do
      self.dispatcher:On(event, function(...) self:HandleEvent(event, ...) end)
    end
  end
  return self
end

function CharacterService:SetProfessionScanner(scanner)
  self.professionScanner = scanner
  return self
end

function CharacterService:GetTimestamp()
  return timestamp(self.env, self.clock)
end

function CharacterService:DiscoverCurrent(seenAt, eventLevel)
  local context, err = currentContext(self, eventLevel)
  if not context then
    self.lastError = err
    return false, err
  end
  seenAt = tonumber(seenAt) or self:GetTimestamp()
  context.lastSeenAt = seenAt
  if not self.repository or type(self.repository.CommitCharacterContext) ~= "function" then
    self.lastError = "repository unavailable"
    return false, self.lastError
  end
  local ok, commitError = self.repository:CommitCharacterContext(context, seenAt)
  if not ok then
    self.lastError = commitError or "character context commit failed"
    return false, self.lastError
  end
  self.currentContext = context
  self.currentProductKey = context.productKey
  self.currentCharacterKey = context.characterKey
  if self.inventory and type(self.inventory.SetCharacter) == "function" then
    self.inventory:SetCharacter(self.currentProductKey, self.currentCharacterKey)
  end
  self.lastError = nil
  return true, context
end

CharacterService.UpdateContext = CharacterService.DiscoverCurrent
CharacterService.DiscoverCharacter = CharacterService.DiscoverCurrent
CharacterService.CommitCurrentContext = CharacterService.DiscoverCurrent

function CharacterService:GetCurrentCharacter()
  if not self.currentProductKey or not self.currentCharacterKey then return nil end
  if self.repository and type(self.repository.GetCharacter) == "function" then
    return self.repository:GetCharacter(self.currentProductKey, self.currentCharacterKey, false)
  end
  return nil
end

function CharacterService:SetTracked(tracked, productKey, characterKey)
  productKey = productKey or self.currentProductKey
  characterKey = characterKey or self.currentCharacterKey
  if not self.repository or type(self.repository.SetTracked) ~= "function" then return false end
  return self.repository:SetTracked(productKey, characterKey, tracked == true)
end

CharacterService.TrackCurrent = function(self) return self:SetTracked(true) end
CharacterService.UntrackCurrent = function(self) return self:SetTracked(false) end

function CharacterService:Forget(productKey, characterKey)
  productKey = productKey or self.currentProductKey
  characterKey = characterKey or self.currentCharacterKey
  if not self.repository or type(self.repository.ForgetCharacter) ~= "function" then return false end
  local ok = self.repository:ForgetCharacter(productKey, characterKey)
  if ok and productKey == self.currentProductKey and characterKey == self.currentCharacterKey then
    self.currentContext, self.currentProductKey, self.currentCharacterKey = nil, nil, nil
  end
  return ok
end

function CharacterService:Reconcile(reconciledAt)
  local ok, contextOrError = self:DiscoverCurrent(reconciledAt)
  local result = { success = ok, context = ok and contextOrError or nil, error = ok and nil or contextOrError }
  if ok and self.professionScanner and type(self.professionScanner.RefreshRanks) == "function" then
    result.professions = self.professionScanner:RefreshRanks(reconciledAt)
    result.success = result.success and result.professions.success
  end
  if ok and self.inventory and type(self.inventory.Reconcile) == "function" then
    result.bags = self.inventory:Reconcile(reconciledAt)
    result.success = result.success and result.bags.success
  end
  return result
end

function CharacterService:OnLogin(seenAt)
  local ok, contextOrError = self:DiscoverCurrent(seenAt)
  local result = { success = ok, context = ok and contextOrError or nil, error = ok and nil or contextOrError }
  if ok and self.inventory and type(self.inventory.OnLogin) == "function" then
    -- PLAYER_LOGIN and PLAYER_ENTERING_WORLD can both arrive during one
    -- loading cycle. Keep the context update, but avoid replacing the same
    -- valid bag snapshot twice in that cycle.
    local stamp = tonumber(seenAt) or self:GetTimestamp()
    if self.lastLoginScanAt ~= stamp then
      result.bags = self.inventory:OnLogin(stamp)
      if result.bags and result.bags.success then self.lastLoginScanAt = stamp end
      result.success = result.bags.success
    end
  end
  return result
end

function CharacterService:OnLogout(seenAt)
  local ok, contextOrError = self:DiscoverCurrent(seenAt)
  local result = { success = ok, context = ok and contextOrError or nil, error = ok and nil or contextOrError }
  if ok and self.inventory and type(self.inventory.OnLogout) == "function" then
    local stamp = tonumber(seenAt) or self:GetTimestamp()
    if self.lastLogoutScanAt ~= stamp then
      result.inventory = self.inventory:OnLogout(stamp)
      self.lastLogoutScanAt = stamp
      result.success = result.inventory.success
    end
  end
  return result
end

function CharacterService:HandleEvent(event, ...)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    return self:OnLogin()
  elseif event == "PLAYER_LEVEL_UP" then
    local level = ...
    local ok, contextOrError = self:DiscoverCurrent(nil, level)
    return { success = ok, context = ok and contextOrError or nil, error = ok and nil or contextOrError }
  elseif event == "PLAYER_LOGOUT" then
    return self:OnLogout()
  elseif self.inventory and type(self.inventory.HandleEvent) == "function" then
    return self.inventory:HandleEvent(event, ...)
  end
end

CharacterService.OnEvent = CharacterService.HandleEvent
CharacterService.OnPlayerLevelUp = function(self, newLevel) return self:HandleEvent("PLAYER_LEVEL_UP", newLevel) end

function CharacterService:StartReconciliation()
  if self.ticker then return self.ticker end
  local timer = self.env and self.env.C_Timer
  if type(timer) == "table" and type(timer.NewTicker) == "function" then
    self.ticker = timer.NewTicker(self.reconcileSeconds, function() self:Reconcile() end)
  elseif type(timer) == "table" and type(timer.After) == "function" then
    -- A one-shot fallback keeps test clients and older runtimes usable.
    self.ticker = { cancelled = false }
    timer.After(self.reconcileSeconds, function()
      if not self.ticker or self.ticker.cancelled then return end
      self:Reconcile()
      self.ticker = nil
    end)
  end
  return self.ticker
end

function CharacterService:StopReconciliation()
  if self.ticker and type(self.ticker.Cancel) == "function" then self.ticker:Cancel() end
  if self.ticker then self.ticker.cancelled = true end
  self.ticker = nil
end
