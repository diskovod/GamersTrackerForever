AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
ACT.ApiCompat = ACT.ApiCompat or {}
local Classic = ACT.ApiCompat.Classic or {}
ACT.ApiCompat.Classic = Classic

-- Inventory APIs changed shape between Classic-era client builds.  The
-- scanner only consumes these small, normalized methods; all API probing is
-- kept here so a future product adapter can implement the same contract.
local function hasFunction(value, name)
  return type(value) == "table" and type(value[name]) == "function"
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  return fn(...)
end

local function number(value, fallback)
  local result = tonumber(value)
  return result == nil and fallback or result
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then
    return nil
  end
  -- Item links have remained stable even when the container API changed.
  return tonumber(link:match("item:(%d+)"))
end

function Classic:GetInventoryContainerIDs()
  local env = self.env or _G
  local result = { 0 }
  local count
  if hasFunction(env, "GetContainerNumSlots") then
    count = tonumber(env.NUM_BAG_SLOTS)
  elseif type(env.C_Container) == "table" then
    count = tonumber(env.NUM_BAG_SLOTS)
  end
  count = count or 4
  for bag = 1, count do
    result[#result + 1] = bag
  end
  return result
end

Classic.GetBagContainerIDs = Classic.GetInventoryContainerIDs
Classic.GetBagIDs = Classic.GetInventoryContainerIDs

function Classic:GetBankContainerIDs()
  local env = self.env or _G
  local result = { -1 }
  local count = tonumber(env.NUM_BANKBAGSLOTS) or 7
  for bag = 5, 4 + count do
    result[#result + 1] = bag
  end
  return result
end

Classic.GetBankIDs = Classic.GetBankContainerIDs

function Classic:SetBankAccessible(value)
  self.bankAccessible = value == true
end

function Classic:IsBankAccessible()
  if self.bankAccessible ~= nil then
    return self.bankAccessible == true
  end
  local env = self.env or _G
  if type(env.IsBagOpen) == "function" then
    local open = env.IsBagOpen(-1)
    if open ~= nil then
      return open == true
    end
  end
  local bankFrame = env.BankFrame
  if type(bankFrame) == "table" and type(bankFrame.IsShown) == "function" then
    return bankFrame:IsShown() == true
  end
  -- Do not infer accessibility merely from bank-slot APIs.  On some clients
  -- those APIs return the last cache while the bank is closed.
  return false
end

function Classic:GetContainerNumSlots(containerID)
  local env = self.env or _G
  local container = env.C_Container
  if hasFunction(container, "GetContainerNumSlots") then
    return number(call(container.GetContainerNumSlots, containerID), 0)
  end
  if type(env.GetContainerNumSlots) == "function" then
    return number(env.GetContainerNumSlots(containerID), 0)
  end
  return 0
end

Classic.GetContainerSlotCount = Classic.GetContainerNumSlots

function Classic:GetContainerItemInfo(containerID, slot)
  local env = self.env or _G
  local container = env.C_Container
  if hasFunction(container, "GetContainerItemInfo") then
    local info = call(container.GetContainerItemInfo, containerID, slot)
    if type(info) ~= "table" then
      return nil
    end
    local link = info.hyperlink or info.link
    return {
      itemID = number(info.itemID, itemIDFromLink(link)),
      quantity = number(info.stackCount or info.count, 0),
      link = link,
      icon = info.iconFileID or info.icon,
      raw = info,
    }
  end

  if type(env.GetContainerItemInfo) ~= "function" then
    return nil
  end
  local texture, count, locked, quality, readable, lootable, link = env.GetContainerItemInfo(containerID, slot)
  local id
  if type(env.GetContainerItemID) == "function" then
    id = env.GetContainerItemID(containerID, slot)
  end
  return {
    itemID = number(id, itemIDFromLink(link)),
    quantity = number(count, 0),
    link = link,
    icon = texture,
    locked = locked,
    quality = quality,
    readable = readable,
    lootable = lootable,
  }
end

function Classic:GetContainerItemID(containerID, slot)
  local info = self:GetContainerItemInfo(containerID, slot)
  return info and number(info.itemID, nil) or nil
end

function Classic:GetContainerItemLink(containerID, slot)
  local info = self:GetContainerItemInfo(containerID, slot)
  return info and info.link or nil
end

Classic.GetItemInfo = Classic.GetContainerItemInfo
Classic.CanScanBank = Classic.IsBankAccessible

function Classic:IsInventoryCapabilityAvailable(location)
  local env = self.env or _G
  local container = env.C_Container
  local available = hasFunction(container, "GetContainerNumSlots") and hasFunction(container, "GetContainerItemInfo")
    or type(env.GetContainerNumSlots) == "function" and type(env.GetContainerItemInfo) == "function"
  if location == "bank" then
    return available and self:IsBankAccessible()
  end
  return available
end
