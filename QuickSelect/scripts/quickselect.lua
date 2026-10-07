-- Support for vanilla and up to 20 slots for: Bigger Action Bar(20 slots)
-- http://steamcommunity.com/sharedfiles/filedetails/?id=853665529
local HOTBAR_SIZE = 20
local SELECTION_CHECK_INTERVAL = 0.05

local ogInit = init
local ogUpdate = update

local lastHotbarSlot
local slotCheckTimer = 0

local inventoryBags = {}

local function safeCall(name, fn, ...)
  if type(fn) ~= "function" then
    sb.logError("[QuickSelect] MISSING API: %s", name)
    return false, nil
  end

  local ok, result = pcall(fn, ...)

  if not ok then
    sb.logError("[QuickSelect] %s FAILED: %s", name, tostring(result))
    return false, nil
  end

  return true, result
end

-- Check for all bags instead of hardcoding vanilla ones.
-- Supported example mod: bk3k's Inventory
-- https://steamcommunity.com/sharedfiles/filedetails/?id=882900100
local function getInventoryBags()
  local bags = root.assetJson("/player.config").inventory.itemBags
  local names = {}

  for name in pairs(bags) do
    names[#names + 1] = name
  end

  return names
end

local function isSameItem(a, b)
  if not a or not b then
    return false
  end

  if type(root.itemDescriptorsMatch) == "function" then
    local ok, result = pcall(root.itemDescriptorsMatch, a, b, false)

    if ok then
      return result
    end
  end

  return a.name == b.name
end

local function targetPosition()
  local ok, aim = safeCall("player.aimPosition", player.aimPosition)

  if not ok or not aim then
    return nil
  end

  return {
    math.floor(aim[1]),
    math.floor(aim[2])
  }
end

-- TODO:
local function materialItemDrop(material)
  if type(material) ~= "string" then
    return nil
  end

  local ok, config = safeCall(
    "root.materialConfig",
    root.materialConfig,
    material
  )

  if not ok or not config or not config.config then
    return nil
  end

  local itemDrop = config.config.itemDrop

  if type(itemDrop) == "string" and itemDrop ~= "" then
    return { name = itemDrop }
  end
end

-- Priority: Foreground -> Objects -> Background
-- TODO: Test on tiles that have more than 1 "foreground" object, eg. platforms + decorations.
local function resolveTargetItem()
  local pos = targetPosition()

  if not pos then
    return nil
  end

  -- Foreground
  local ok, material = safeCall("world.material", world.material, pos, "foreground")

  if ok then
    local item = materialItemDrop(material)

    if item then
      return item
    end
  end

  -- Object
  local objectOk, objectId = safeCall("world.objectAt", world.objectAt, pos)

  if objectOk and objectId then
    local nameOk, objectName = safeCall(
      "world.entityName",
      world.entityName,
      objectId
    )

    if nameOk and type(objectName) == "string" then
      return { name = objectName }
    end
  end

  -- Background material
  local materialOk, material = safeCall("world.material", world.material, pos, "background")

  -- TODO: Add support for liquids?
  if materialOk then
    return materialItemDrop(material)
  end
end

local function getSelectedHotbarSlot()
  local ok, slot = safeCall(
    "player.selectedActionBarSlot",
    player.selectedActionBarSlot
  )

  if ok and type(slot) == "number" then
    return slot
  end
end

local function getHotbarItemAt(slot)
  --TODO: Check both hands
  local link = player.actionBarSlotLink(slot, "primary")

  if not link then
    return nil
  end

  return player.item(link)
end

local function findHotbarItem(targetItem)
  for slot = 1, HOTBAR_SIZE do
    local item = getHotbarItemAt(slot)

    if item and isSameItem(item, targetItem) then
      return slot
    end
  end
end

local function findEmptyHotbarSlot()
  for slot = 1, HOTBAR_SIZE do
    if not getHotbarItemAt(slot) then
      return slot
    end
  end
end

local function findItemInInventory(targetItem)
  for _, bagName in ipairs(inventoryBags) do
    local size = player.itemBagSize(bagName)

    if type(size) == "number" then
      for slot = 0, size - 1 do
        local inventorySlot = { bagName, slot }
        local item = player.item(inventorySlot)

        if item and isSameItem(item, targetItem) then
          return inventorySlot
        end
      end
    end
  end
end

local function clearItemInHand()
  return safeCall(
    "player.setSelectedActionBarSlot",
    player.setSelectedActionBarSlot,
    nil
  )
end

local function selectHotbarSlot(slot)
  return safeCall(
    "player.setSelectedActionBarSlot",
    player.setSelectedActionBarSlot,
    slot
  )
end

local function setHotbarLink(hotbarSlot, inventorySlot)
  local ok = safeCall(
    "player.setActionBarSlotLink",
    player.setActionBarSlotLink,
    hotbarSlot,
    "primary",
    inventorySlot
  )

  if not ok then
    return false
  end

  return selectHotbarSlot(hotbarSlot)
end

local function quickSelect()
  local targetItem = resolveTargetItem()

  -- Nothing to select
  if not targetItem then
    clearItemInHand()
    return
  end

  -- Already on hotbar
  local hotbarSlot = findHotbarItem(targetItem)

  if hotbarSlot then
    selectHotbarSlot(hotbarSlot)
    return
  end

  -- Find in inventory
  local inventorySlot = findItemInInventory(targetItem)

  -- Not present on inventory, deselect
  if not inventorySlot then
    clearItemInHand()
    return
  end

  -- Prefer setting the current selected slot (if empty)
  local selected = getSelectedHotbarSlot()

  if selected and not getHotbarItemAt(selected) then
    if setHotbarLink(selected, inventorySlot) then
      return
    end
  end

  -- Otherwise use first empty slot
  local emptySlot = findEmptyHotbarSlot()

  if emptySlot and setHotbarLink(emptySlot, inventorySlot) then
    return
  end

  -- All slots occupied, use the previously selected slot
  if lastHotbarSlot then
    setHotbarLink(lastHotbarSlot, inventorySlot)
  end
end

local function rememberSelectedSlot()
  local selected = getSelectedHotbarSlot()

  if selected then
    lastHotbarSlot = selected
  end
end



function update(dt, ...)
  -- Throttle the last slot checks, probably had negligible impact, but oh well...
  slotCheckTimer = slotCheckTimer - (dt or 0)

  if slotCheckTimer <= 0 then
    slotCheckTimer = SELECTION_CHECK_INTERVAL
    rememberSelectedSlot()
  end

  if input.bindDown("QuickSelect", "quickSelect") then
    quickSelect()
  end

  if ogUpdate then
    ogUpdate(dt, ...)
  end
end

function init(...)
  local ok, bags = safeCall("getInventoryBags", getInventoryBags)

  if not ok then
    return
  end

  inventoryBags = bags

  sb.logInfo("[QuickSelect] LOADED (%s inventory bags)", #inventoryBags)

  if ogInit then
    ogInit(...)
  end
end
