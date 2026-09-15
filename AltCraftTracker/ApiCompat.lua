AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local ApiCompat = {}
ACT.ApiCompat = ApiCompat

local function normalize(value)
  if value == nil or value == "" then
    return "unknown"
  end
  value = tostring(value):lower()
  value = value:gsub("[^%w%-]", "-")
  return value
end

local function hasFunction(env, name)
  return type(env[name]) == "function"
end

local function safeString(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

local Classic = {}
Classic.__index = Classic

function Classic:ReadClientInfo()
  local version, build, date, interface = "", "", "", 0
  if hasFunction(self.env, "GetBuildInfo") then
    version, build, date, interface = self.env.GetBuildInfo()
  end
  return {
    productID = self.env.WOW_PROJECT_ID or self.env.WOW_PROJECT_CLASSIC_ERA or 0,
    product = self.productKey or ACT.PRODUCT_CLASSIC_ERA,
    version = safeString(version),
    build = safeString(build),
    date = safeString(date),
    interface = tonumber(interface) or 0,
  }
end

function Classic:GetClientInfo()
  self.clientInfo = self:ReadClientInfo()
  return self.clientInfo
end

function Classic:GetProduct()
  return self.productKey or ACT.PRODUCT_CLASSIC_ERA
end

function Classic:GetCurrentIdentity()
  local env = self.env
  local name, realm
  if hasFunction(env, "UnitFullName") then
    name, realm = env.UnitFullName("player")
  elseif hasFunction(env, "UnitName") then
    name, realm = env.UnitName("player")
  end
  if not realm or realm == "" then
    if hasFunction(env, "GetRealmName") then
      realm = env.GetRealmName()
    end
  end

  local localizedClass, classToken, classID
  if hasFunction(env, "UnitClass") then
    localizedClass, classToken, classID = env.UnitClass("player")
  end
  local faction = ""
  if hasFunction(env, "UnitFactionGroup") then
    faction = env.UnitFactionGroup("player") or ""
  end
  local guid
  if hasFunction(env, "UnitGUID") then
    guid = env.UnitGUID("player")
  end

  return {
    guid = safeString(guid),
    displayName = safeString(name),
    realm = realm,
    region = nil,
    ruleset = "classic_era",
    faction = safeString(faction),
    classID = tonumber(classID or classToken) or 0,
    className = safeString(localizedClass),
  }
end

function Classic:GetCharacterKey(identity)
  identity = identity or self:GetCurrentIdentity()
  if identity.guid and identity.guid ~= "" then
    return identity.guid
  end
  return table.concat({
    ACT.PRODUCT_CLASSIC_ERA,
    normalize(identity.realm),
    normalize(identity.displayName),
    normalize(identity.faction),
  }, "|")
end

function Classic:GetTransferGroup(identity)
  identity = identity or self:GetCurrentIdentity()
  return table.concat({
    ACT.PRODUCT_CLASSIC_ERA,
    normalize(identity.realm),
    normalize(identity.faction),
  }, "|")
end

function Classic:GetCurrentContext()
  local identity = self:GetCurrentIdentity()
  local level = 0
  if hasFunction(self.env, "UnitLevel") then
    level = tonumber(self.env.UnitLevel("player")) or 0
  end
  identity.transferGroup = self:GetTransferGroup(identity)
  return {
    key = self:GetCharacterKey(identity),
    identity = identity,
    level = level,
    client = self:GetClientInfo(),
    transferGroup = identity.transferGroup,
  }
end

function Classic:GetCapabilities()
  local env = self.env
  local container = env.C_Container
  local hasContainer = type(container) == "table"
    and hasFunction(container, "GetContainerNumSlots")
    and hasFunction(container, "GetContainerItemInfo")
  local hasLegacyContainer = hasFunction(env, "GetContainerNumSlots")
    and (hasFunction(env, "GetContainerItemInfo") or hasFunction(env, "GetContainerItemLink"))

  return {
    [ACT.CAPABILITY.PRODUCT_DETECTION] = hasFunction(env, "GetBuildInfo") or env.WOW_PROJECT_ID ~= nil,
    [ACT.CAPABILITY.CHARACTER_IDENTITY] = hasFunction(env, "UnitName") or hasFunction(env, "UnitFullName"),
    [ACT.CAPABILITY.CHARACTER_LEVEL] = hasFunction(env, "UnitLevel"),
    [ACT.CAPABILITY.PROFESSION_ENUMERATION] = hasFunction(env, "GetProfessions") and hasFunction(env, "GetProfessionInfo"),
    [ACT.CAPABILITY.LEARNED_RECIPE_SCAN] = hasFunction(env, "GetTradeSkillLine") and hasFunction(env, "GetNumTradeSkills") and hasFunction(env, "GetTradeSkillInfo"),
    [ACT.CAPABILITY.BAG_INVENTORY_SCAN] = hasContainer or hasLegacyContainer,
    [ACT.CAPABILITY.BANK_INVENTORY_SCAN] = hasContainer or hasLegacyContainer,
    [ACT.CAPABILITY.SAVED_VARIABLES] = true,
    [ACT.CAPABILITY.TRANSFER_GROUP] = hasFunction(env, "UnitFactionGroup") and (hasFunction(env, "GetRealmName") or hasFunction(env, "UnitFullName")),
    [ACT.CAPABILITY.EVENT_DISPATCH] = true,
    [ACT.CAPABILITY.SLASH_COMMANDS] = true,
  }
end

function ApiCompat.CreateClassic(env, productKey)
  local adapter = setmetatable({ env = env or _G, productKey = productKey or ACT.PRODUCT_CLASSIC_ERA }, Classic)
  adapter.clientInfo = adapter:ReadClientInfo()
  return adapter
end

function ApiCompat.Detect(env)
  env = env or _G
  local projectID = env.WOW_PROJECT_ID
  local classicID = env.WOW_PROJECT_CLASSIC_ERA or env.WOW_PROJECT_CLASSIC
  local isClassic = projectID == nil or (classicID ~= nil and projectID == classicID) or projectID == 2
  if isClassic then
    return ApiCompat.CreateClassic(env), ACT.PRODUCT_CLASSIC_ERA
  end
  -- The Classic .toc is not a Forever adapter. Keep the probe useful while
  -- making an unvalidated product visible instead of silently claiming support.
  local productKey = "unsupported:" .. tostring(projectID)
  return ApiCompat.CreateClassic(env, productKey), productKey
end

ACT.ApiCompat.Classic = Classic
