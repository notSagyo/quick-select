-- TODO: Verify categories
-- Lower values are replaced first
-- 0 to 100 reserved for categories priority
-- 100 to 999 reserved for custom items priority
-- 1000 is the fallback for any item that did't match any filter
local CATEGORY_PRIORITY = {
  block = 0,
  platform = 0,

  actionfigure = 1,
  artifact = 1,
  breakable = 1,
  bug = 1,
  crafting = 1,
  decorative = 1,
  door = 1,
  fridgestorage = 1,
  furniture = 1,
  light = 1,
  other = 1,
  playerstation = 1,
  rail = 1,
  railpoint = 1,
  sapling = 1,
  seed = 1,
  shippingcontainer = 1,
  storage = 1,
  techmanagement = 1,
  teleporter = 1,
  terraformer = 1,

  farmbeastegg = 2,
  genboss = 2,
  trap = 2,
  wire = 2,
}

-- Platforms and torches can be used as exploring tools rather than building blocks
local ITEM_PRIORITY = {
  woodenplatform = 100,
  torch = 101
}

local function getItemPriority(item)
  if not item then
    return nil
  end

  -- Check for item priority first
  local priority = ITEM_PRIORITY[item.name]

  if priority ~= nil then
    return priority
  end

  -- Check for category priority second
  local config = root.itemConfig(item)

  if not config or not config.config then
    return 1000
  end

  local itemConfig = config.config
  local category = itemConfig.category
  priority = nil

  if type(category) == "string" then
    -- Normalize categories' names
    category = string.lower(category):gsub("[^%w]", "")
    priority = CATEGORY_PRIORITY[category]
  end

  -- Categories can be shared by non-placeable items, treat them as placeable when their config has an objectName
  if type(itemConfig.objectName) == "string" then
    if priority ~= nil then
      return priority
    end

    return 1000
  end

  -- Blocks, platforms, and rails are placeable materials, however their configs have category but no objectName
  if priority ~= nil and root.itemType(item.name) == "material" then
    return priority
  end

  return 1000
end

-- TODO: Test all cases and edge cases in game
local function findHotbarSlot(targetItem, hotbarSize, getHotbarItemAt, selectedSlot)
  local incomingPriority = getItemPriority(targetItem)
  local samePrioritySlot
  local currentSlot
  local currentBestSlot
  local currentBestPriority

  for i = 1, hotbarSize do
    local item = getHotbarItemAt(i)

    if item then
      local priority = getItemPriority(item)

      if i == selectedSlot then
        currentSlot = {
          index = i,
          item = item,
          priority = priority
        }
      end

      if samePrioritySlot == nil and priority == incomingPriority then
        samePrioritySlot = i
      end

      if currentBestPriority == nil or priority < currentBestPriority then
        currentBestSlot = i
        currentBestPriority = priority
      end
    end
  end

  -- Prefer replacing recognized placeables in the selected slot, unless it has item-specific priority
  if currentSlot and ITEM_PRIORITY[currentSlot.item.name] == nil
      and (currentSlot.priority < 100) then
    return currentSlot.index
  end

  -- Prefer the first slot with same priority as incoming item, otherwise lowest priority value candidate
  return samePrioritySlot or currentBestSlot
end

quickselectSmart = {
  findHotbarSlot = findHotbarSlot
}
