AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local InventoryScanner = {}
InventoryScanner.__index = InventoryScanner
ACT.InventoryScanner = InventoryScanner

local function now(env, clock)
  if type(clock) == "function" then
    return tonumber(clock()) or 0
  end
  if env and type(env.time) == "function" then
    return tonumber(env.time()) or 0
  end
  if env and type(env.GetServerTime) == "function" then
    return tonumber(env.GetServerTime()) or 0
  end
  if type(ACT.Now) == "function" then
    return tonumber(ACT.Now()) or 0
  end
  return 0
end

local function positiveInteger(value)
  local number = tonumber(value)
  if number and number > 0 and number == math.floor(number) then
    return number
  end
  return nil
end

local function resolveKeys(self)
  if self.productKey and self.characterKey then
    return self.productKey, self.characterKey
  end
  if self.api and type(self.api.GetCurrentContext) == "function" then
    local context = self.api:GetCurrentContext()
    self.productKey = context.productKey or context.product or (context.client and context.client.product) or (self.api.GetProduct and self.api:GetProduct())
    self.characterKey = context.characterKey or context.key
  end
  return self.productKey, self.characterKey
end

local function scheduleTimer(self, callback)
  local timer = self.env and self.env.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(self.debounceSeconds, callback)
    return true
  end
  return false
end

function InventoryScanner:Create(env, api, repository, options)
  -- Accept the conventional (env, api, repository) form and the convenient
  -- (api, repository, options) form used by out-of-client fixture tests.
  if env and type(env.GetContainerNumSlots) == "function" and api and type(api.CommitBagsSnapshot) == "function" then
    repository, options, api, env = api, repository, env, _G
  elseif env and type(env.GetContainerNumSlots) == "function" and api == nil then
    api, env = env, _G
  elseif type(env) == "table" and (env.api or env.repository) and api == nil then
    options, api, repository, env = env, env.api, env.repository, env.env or _G
  end
  options = options or {}
  local scanner = setmetatable({
    env = env or _G,
    api = api,
    repository = repository,
    clock = options.clock,
    onResult = options.onResult,
    debounceSeconds = tonumber(options.debounceSeconds) or 0.15,
    pendingBags = false,
    pendingBank = false,
    bankOpen = false,
    lastResults = {},
    lastError = nil,
    productKey = options.productKey,
    characterKey = options.characterKey,
  }, InventoryScanner)
  return scanner
end

function InventoryScanner:Initialize(api, repository, options)
  if api then self.api = api end
  if repository then self.repository = repository end
  if options then
    self.productKey = options.productKey or self.productKey
    self.characterKey = options.characterKey or self.characterKey
    self.clock = options.clock or self.clock
    self.onResult = options.onResult or self.onResult
  end
  return self
end

function InventoryScanner:GetTimestamp()
  return now(self.env, self.clock)
end

function InventoryScanner:SetCharacter(productKey, characterKey)
  self.productKey, self.characterKey = productKey, characterKey
end

function InventoryScanner:Notify(result)
  if type(self.onResult) == "function" then pcall(self.onResult, result) end
end

function InventoryScanner:IsBankAccessible()
  if self.bankOpen then
    return true
  end
  return self.api and type(self.api.IsBankAccessible) == "function" and self.api:IsBankAccessible() == true
end

function InventoryScanner:ScanContainers(containerIDs)
  if type(containerIDs) ~= "table" or not self.api
    or type(self.api.GetContainerNumSlots) ~= "function"
    or type(self.api.GetContainerItemInfo) ~= "function" then
    return nil, "container API unavailable"
  end
  local totals = {}
  for _, containerID in ipairs(containerIDs) do
    local slots = tonumber(self.api:GetContainerNumSlots(containerID))
    if slots == nil or slots < 0 then
      return nil, "invalid container slot count"
    end
    for slot = 1, slots do
      local info = self.api:GetContainerItemInfo(containerID, slot)
      if type(info) == "table" then
        local itemID = positiveInteger(info.itemID)
        local quantity = tonumber(info.quantity or info.stackCount or info.count)
        if itemID and quantity and quantity > 0 then
          quantity = math.floor(quantity)
          totals[itemID] = (totals[itemID] or 0) + quantity
        end
      end
    end
  end
  return totals
end

function InventoryScanner:CommitKeys()
  local productKey, characterKey = resolveKeys(self)
  if not productKey or not characterKey then
    return nil, nil, "current character context unavailable"
  end
  return productKey, characterKey
end

function InventoryScanner:ScanBags(scannedAt)
  scannedAt = tonumber(scannedAt) or self:GetTimestamp()
  local productKey, characterKey, keyError = self:CommitKeys()
  if keyError then
    self.lastError = keyError
    return { success = false, complete = false, location = "bags", error = keyError }
  end
  local ids = self.api.GetBagContainerIDs and self.api:GetBagContainerIDs()
    or self.api.GetInventoryContainerIDs and self.api:GetInventoryContainerIDs()
  local totals, err = self:ScanContainers(ids)
  if not totals then
    self.lastError = err
    return { success = false, complete = false, location = "bags", error = err }
  end
  local result = { success = true, complete = true, bags = totals, bagsScannedAt = scannedAt, location = "bags" }
  if self.repository and type(self.repository.CommitBagsSnapshot) == "function" then
    local ok, commitError = self.repository:CommitBagsSnapshot(productKey, characterKey, totals, scannedAt)
    if not ok then
      self.lastError = commitError or "bag snapshot commit failed"
      result.success, result.complete, result.error = false, false, self.lastError
      return result
    end
  end
  self.lastError = nil
  self.lastResults.bags = result
  self:Notify(result)
  return result
end

function InventoryScanner:ScanBank(scannedAt)
  scannedAt = tonumber(scannedAt) or self:GetTimestamp()
  if not self:IsBankAccessible() then
    local result = { success = false, complete = false, accessible = false, location = "bank", error = "bank is inaccessible" }
    self.lastResults.bank = result
    return result
  end
  local productKey, characterKey, keyError = self:CommitKeys()
  if keyError then
    self.lastError = keyError
    return { success = false, complete = false, accessible = true, location = "bank", error = keyError }
  end
  local ids = self.api.GetBankContainerIDs and self.api:GetBankContainerIDs()
  -- BANK_CONTAINER has slots whenever the bank is genuinely readable.  A
  -- closed/inaccessible client commonly reports zero here even though it
  -- still exposes the previous cache; never turn that cache into an empty
  -- successful snapshot.
  if type(self.api.GetContainerNumSlots) == "function" then
    local bankSlots = tonumber(self.api:GetContainerNumSlots(-1))
    if bankSlots ~= nil and bankSlots <= 0 then
      local result = { success = false, complete = false, accessible = false, location = "bank", error = "bank containers are unavailable" }
      self.lastResults.bank = result
      return result
    end
  end
  local totals, err = self:ScanContainers(ids)
  if not totals then
    self.lastError = err
    return { success = false, complete = false, accessible = true, location = "bank", error = err }
  end
  local result = { success = true, complete = true, accessible = true, bank = totals, bankScannedAt = scannedAt, location = "bank" }
  if self.repository and type(self.repository.CommitBankSnapshot) == "function" then
    local ok, commitError = self.repository:CommitBankSnapshot(productKey, characterKey, totals, scannedAt, true)
    if not ok then
      self.lastError = commitError or "bank snapshot commit failed"
      result.success, result.complete, result.error = false, false, self.lastError
      return result
    end
  end
  self.lastError = nil
  self.lastResults.bank = result
  self:Notify(result)
  return result
end

InventoryScanner.ScanBagInventory = InventoryScanner.ScanBags
InventoryScanner.ScanBankInventory = InventoryScanner.ScanBank

function InventoryScanner:ScanAll(scannedAt, includeBank)
  local result = { success = true, complete = true, bags = self:ScanBags(scannedAt) }
  if includeBank == true or self:IsBankAccessible() then
    result.bank = self:ScanBank(scannedAt)
  end
  result.success = result.bags.success and (not result.bank or result.bank.success)
  result.complete = result.success
  return result
end

function InventoryScanner:FlushPending(scannedAt)
  local bags, bank
  if self.pendingBags then
    self.pendingBags = false
    bags = self:ScanBags(scannedAt)
  end
  if self.pendingBank then
    self.pendingBank = false
    bank = self:ScanBank(scannedAt)
  end
  return bags, bank
end

function InventoryScanner:QueueBags()
  if self.pendingBags then return false end
  self.pendingBags = true
  scheduleTimer(self, function() self:FlushPending() end)
  return true
end

function InventoryScanner:QueueBank()
  if self.pendingBank then return false end
  self.pendingBank = true
  scheduleTimer(self, function() self:FlushPending() end)
  return true
end

function InventoryScanner:HandleEvent(event, ...)
  if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
    self:QueueBags()
  elseif event == "BANKFRAME_OPENED" then
    self.bankOpen = true
    if self.api and type(self.api.SetBankAccessible) == "function" then self.api:SetBankAccessible(true) end
    self:QueueBank()
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    if self:IsBankAccessible() then self:QueueBank() end
  elseif event == "BANKFRAME_CLOSED" then
    -- Scan while the client still exposes bank slots, then preserve the
    -- successful snapshot once access is revoked.
    if self:IsBankAccessible() then self:ScanBank() end
    self.pendingBank = false
    self.bankOpen = false
    if self.api and type(self.api.SetBankAccessible) == "function" then self.api:SetBankAccessible(false) end
  end
end

InventoryScanner.OnEvent = InventoryScanner.HandleEvent

function InventoryScanner:Reconcile(scannedAt)
  local result = self:ScanBags(scannedAt)
  return result
end

function InventoryScanner:OnLogin(scannedAt)
  return self:ScanBags(scannedAt)
end

function InventoryScanner:OnLogout(scannedAt)
  -- In-flight debounce callbacks cannot be cancelled on all Classic builds.
  -- Clear their pending flags first so a late callback becomes a no-op rather
  -- than performing a second post-logout write.
  self.pendingBags = false
  self.pendingBank = false
  local result = self:ScanBags(scannedAt)
  if self:IsBankAccessible() then result.bank = self:ScanBank(scannedAt) end
  return result
end
