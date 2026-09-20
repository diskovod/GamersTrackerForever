GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local ApiCompat = {}
GTF.ApiCompat = ApiCompat

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

-- Classic Era and Season of Discovery currently report the 1.15.x client
-- family.  Project constants alone are not sufficient: the Forever beta has
-- been observed with a Classic-looking project id while reporting 1.60.x.
-- Keep this gate deliberately narrow until a Forever adapter is validated.
local function isVerifiedClassicClient(env)
  if not hasFunction(env, "GetBuildInfo") then
    return false
  end
  local version = env.GetBuildInfo()
  return type(version) == "string" and version:match("^1%.15%.[0-9]+") ~= nil
end

function Classic:ReadClientInfo()
  local version, build, date, interface = "", "", "", 0
  if hasFunction(self.env, "GetBuildInfo") then
    version, build, date, interface = self.env.GetBuildInfo()
  end
  return {
    productID = self.env.WOW_PROJECT_ID or self.env.WOW_PROJECT_CLASSIC_ERA or 0,
    product = self.productKey or GTF.PRODUCT_CLASSIC_ERA,
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
  return self.productKey or GTF.PRODUCT_CLASSIC_ERA
end

function Classic:IsSupported()
  return true
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
    GTF.PRODUCT_CLASSIC_ERA,
    normalize(identity.realm),
    normalize(identity.displayName),
    normalize(identity.faction),
  }, "|")
end

function Classic:GetTransferGroup(identity)
  identity = identity or self:GetCurrentIdentity()
  return table.concat({
    GTF.PRODUCT_CLASSIC_ERA,
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
    [GTF.CAPABILITY.PRODUCT_DETECTION] = hasFunction(env, "GetBuildInfo") or env.WOW_PROJECT_ID ~= nil,
    [GTF.CAPABILITY.CHARACTER_IDENTITY] = hasFunction(env, "UnitName") or hasFunction(env, "UnitFullName"),
    [GTF.CAPABILITY.CHARACTER_LEVEL] = hasFunction(env, "UnitLevel"),
    [GTF.CAPABILITY.PROFESSION_ENUMERATION] = hasFunction(env, "GetProfessions") and hasFunction(env, "GetProfessionInfo"),
    [GTF.CAPABILITY.LEARNED_RECIPE_SCAN] = hasFunction(env, "GetTradeSkillLine") and hasFunction(env, "GetNumTradeSkills") and hasFunction(env, "GetTradeSkillInfo"),
    [GTF.CAPABILITY.BAG_INVENTORY_SCAN] = hasContainer or hasLegacyContainer,
    [GTF.CAPABILITY.BANK_INVENTORY_SCAN] = hasContainer or hasLegacyContainer,
    [GTF.CAPABILITY.SAVED_VARIABLES] = true,
    [GTF.CAPABILITY.TRANSFER_GROUP] = hasFunction(env, "UnitFactionGroup") and (hasFunction(env, "GetRealmName") or hasFunction(env, "UnitFullName")),
    [GTF.CAPABILITY.EVENT_DISPATCH] = true,
    [GTF.CAPABILITY.SLASH_COMMANDS] = true,
    [GTF.CAPABILITY.FOREVER_COMPATIBILITY_PROBE] = true,
    [GTF.CAPABILITY.SAVED_VARIABLES_PRODUCT_PARTITIONS] = true,
  }
end

function ApiCompat.CreateClassic(env, productKey)
  local adapter = setmetatable({ env = env or _G, productKey = productKey or GTF.PRODUCT_CLASSIC_ERA }, Classic)
  adapter.clientInfo = adapter:ReadClientInfo()
  return adapter
end

local Unsupported = {}
Unsupported.__index = Unsupported

function Unsupported:ReadClientInfo()
  local version, build, date, interface = "", "", "", 0
  if hasFunction(self.env, "GetBuildInfo") then
    version, build, date, interface = self.env.GetBuildInfo()
  end
  return {
    productID = self.env.WOW_PROJECT_ID or 0,
    product = self.productKey,
    version = safeString(version),
    build = safeString(build),
    date = safeString(date),
    interface = tonumber(interface) or 0,
  }
end

function Unsupported:GetClientInfo()
  self.clientInfo = self:ReadClientInfo()
  return self.clientInfo
end

function Unsupported:GetProduct()
  return self.productKey
end

function Unsupported:GetCurrentContext()
  return nil, "unsupported product; no Classic adapter selected"
end

function Unsupported:GetCapabilities()
  return {
    [GTF.CAPABILITY.PRODUCT_DETECTION] = true,
    [GTF.CAPABILITY.SAVED_VARIABLES] = true,
    [GTF.CAPABILITY.SLASH_COMMANDS] = true,
    [GTF.CAPABILITY.EVENT_DISPATCH] = true,
    [GTF.CAPABILITY.FOREVER_COMPATIBILITY_PROBE] = true,
    [GTF.CAPABILITY.SAVED_VARIABLES_PRODUCT_PARTITIONS] = true,
  }
end

function Unsupported:IsSupported()
  return false
end

function ApiCompat.CreateUnsupported(env, productKey)
  local adapter = setmetatable({ env = env or _G, productKey = productKey or "unsupported:unknown" }, Unsupported)
  adapter.clientInfo = adapter:ReadClientInfo()
  return adapter
end

function ApiCompat.Detect(env)
  env = env or _G
  local projectID = env.WOW_PROJECT_ID
  local classicID = env.WOW_PROJECT_CLASSIC_ERA or env.WOW_PROJECT_CLASSIC
  local verifiedBuild = isVerifiedClassicClient(env)
  local isClassic = verifiedBuild and (projectID == nil
    or (classicID ~= nil and projectID == classicID)
    or projectID == 2)
  if isClassic then
    return ApiCompat.CreateClassic(env), GTF.PRODUCT_CLASSIC_ERA
  end
  -- The Classic .toc is not a Forever adapter. Keep the probe useful while
  -- making an unvalidated product visible.  Never return the Classic adapter
  -- for an unverified build, even when a beta reuses project id 2.
  local productKey = "unsupported:" .. tostring(projectID or "unknown")
  return ApiCompat.CreateUnsupported(env, productKey), productKey
end

GTF.ApiCompat.Classic = Classic
GTF.ApiCompat.Unsupported = Unsupported
