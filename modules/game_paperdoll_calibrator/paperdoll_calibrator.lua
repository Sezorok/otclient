local controller = Controller:new()
local ui = nil

-- State
local state = {
  slot = 'head',           -- current slot name: 'head','body','left','right', etc.
  perItem = false,         -- adjust per-item (true) or slot default (false)
  step = 1,                -- base nudge step
}

local VALID_SLOTS = {
  head = true, body = true, back = true, left = true, right = true,
  legs = true, feet = true, neck = true, finger = true, ammo = true, purse = true
}

local function getCurrentDirKey()
  if paperdoll_get_current_dir_key then
    return paperdoll_get_current_dir_key()
  end
  return 'S'
end

local function getCurrentItemId(slotName)
  local p = g_game.getLocalPlayer(); if not p then return nil end
  local invMap = {
    head = InventorySlotHead, neck = InventorySlotNeck, back = InventorySlotBack, body = InventorySlotBody,
    right = InventorySlotRight, left = InventorySlotLeft, legs = InventorySlotLeg, feet = InventorySlotFeet,
    finger = InventorySlotFinger, ammo = InventorySlotAmmo, purse = InventorySlotPurse
  }
  local s = invMap[slotName]
  if not s then return nil end
  local it = p:getInventoryItem(s)
  return it and it:getId() or nil
end

local function applyAndRefresh(slotName, itemId)
  if state.perItem then
    if paperdoll_update_manager_config then paperdoll_update_manager_config(slotName, itemId) end
  end
  if paperdoll_apply_slot then paperdoll_apply_slot(slotName) end
end

local function nudge(slotName, dirKey, dx, dy)
  if not VALID_SLOTS[slotName] then
    g_logger.info('[paperdoll] invalid slot: '.. tostring(slotName))
    return
  end
  local step = state.step
  local mods = g_keyboard.getModifiers and g_keyboard.getModifiers() or {}
  if mods.shift then step = step * 5 end
  if mods.ctrl then step = math.max(1, math.floor(step / 2)) end
  local nx, ny = (dx or 0) * step, (dy or 0) * step

  if state.perItem then
    local itemId = getCurrentItemId(slotName)
    if not itemId then
      g_logger.info('[paperdoll] sem item equipado no slot '..slotName)
      return
    end
    local fn = _G['paperdoll_nudge_'..slotName..'_item']
    if fn then
      local v = fn(dirKey, nx, ny)
      g_logger.info(string.format('[paperdoll] %s item %d %s => (%d,%d,%s)', slotName, itemId, dirKey, v[1] or 0, v[2] or 0, v[3] and true or false))
      applyAndRefresh(slotName, itemId)
    else
      -- generic per-item setter if specific not available
      if paperdoll_set_item_offsets then
        -- read current, then apply delta
        local map = { N = {0,0,true}, E = {0,0,true}, S = {0,0,true}, W = {0,0,true} }
        map[dirKey][1] = (map[dirKey][1] or 0) + nx
        map[dirKey][2] = (map[dirKey][2] or 0) + ny
        paperdoll_set_item_offsets(slotName, itemId, map, true)
      end
    end
  else
    local fn = _G['paperdoll_nudge_'..slotName]
    if fn then
      local v = fn(dirKey, nx, ny)
      g_logger.info(string.format('[paperdoll] %s default %s => (%d,%d,%s)', slotName, dirKey, v[1] or 0, v[2] or 0, v[3] and true or false))
      applyAndRefresh(slotName, getCurrentItemId(slotName))
    else
      -- generic default setter
      if paperdoll_set_slot_offsets then
        local map = { N = {0,0,true}, E = {0,0,true}, S = {0,0,true}, W = {0,0,true} }
        map[dirKey][1] = (map[dirKey][1] or 0) + nx
        map[dirKey][2] = (map[dirKey][2] or 0) + ny
        paperdoll_set_slot_offsets(slotName, map, true)
      end
    end
  end
end

local function togglePerItem()
  state.perItem = not state.perItem
  g_logger.info('[paperdoll] modo: '.. (state.perItem and 'por item' or 'padrão do slot'))
end

local function selectSlot(name)
  if VALID_SLOTS[name] then
    state.slot = name
    g_logger.info('[paperdoll] slot selecionado: '.. name)
  else
    g_logger.info('[paperdoll] slot inválido: '.. tostring(name))
  end
end

local function saveOffsets()
  if _G['savePaperdollOffsets'] then _G['savePaperdollOffsets']() end
  g_logger.info('[paperdoll] offsets salvos')
end

local function clearItem()
  local itemId = getCurrentItemId(state.slot)
  if not itemId then
    g_logger.info('[paperdoll] sem item equipado para limpar')
    return
  end
  if _G['paperdoll_clear_'..state.slot..'_item_offsets'] then
    _G['paperdoll_clear_'..state.slot..'_item_offsets']()
  elseif paperdoll_clear_item_offsets then
    paperdoll_clear_item_offsets(state.slot, itemId)
  end
  g_logger.info(string.format('[paperdoll] offsets do item %d em %s limpos', itemId, state.slot))
end

local function bump(dir)
  local dk = getCurrentDirKey()
  if dir == 'up' then nudge(state.slot, dk, 0, -1)
  elseif dir == 'down' then nudge(state.slot, dk, 0, 1)
  elseif dir == 'left' then nudge(state.slot, dk, -1, 0)
  elseif dir == 'right' then nudge(state.slot, dk, 1, 0) end
end

local function bindKeys()
  -- Nudges in current facing dir
  controller:bindKeyDown('Alt+Up', function() bump('up') end)
  controller:bindKeyDown('Alt+Down', function() bump('down') end)
  controller:bindKeyDown('Alt+Left', function() bump('left') end)
  controller:bindKeyDown('Alt+Right', function() bump('right') end)

  -- Slot quick selection
  controller:bindKeyDown('Alt+1', function() selectSlot('head') end)
  controller:bindKeyDown('Alt+2', function() selectSlot('body') end)
  controller:bindKeyDown('Alt+3', function() selectSlot('back') end)
  controller:bindKeyDown('Alt+4', function() selectSlot('left') end)
  controller:bindKeyDown('Alt+5', function() selectSlot('right') end)
  controller:bindKeyDown('Alt+6', function() selectSlot('legs') end)
  controller:bindKeyDown('Alt+7', function() selectSlot('feet') end)
  controller:bindKeyDown('Alt+8', function() selectSlot('neck') end)
  controller:bindKeyDown('Alt+9', function() selectSlot('finger') end)
  controller:bindKeyDown('Alt+0', function() selectSlot('ammo') end)

  -- Toggle per-item vs default
  controller:bindKeyDown('Alt+P', togglePerItem)

  -- Save and clear
  controller:bindKeyDown('Alt+S', saveOffsets)
  controller:bindKeyDown('Alt+C', clearItem)
end

function init()
  controller:init()
  bindKeys()
  -- Load UI window
  ui = g_ui.displayUI('paperdoll_calibrator')
  -- Populate slot combo
  local slotBox = ui.slotBox
  for name, _ in pairs(VALID_SLOTS) do
    slotBox:addOption(name, name)
  end
  slotBox:setCurrentOptionByData(state.slot)
  slotBox.onOptionChange = function(widget, text, data)
    selectSlot(data)
  end
  -- Step combo
  local stepBox = ui.stepBox
  stepBox:addOption('1', 1)
  stepBox:addOption('2', 2)
  stepBox:addOption('5', 5)
  stepBox:addOption('10', 10)
  stepBox:setCurrentOptionByData(state.step)
  stepBox.onOptionChange = function(widget, text, data)
    state.step = tonumber(data) or 1
  end
  -- Per-item toggle
  ui.perItemCheck:setChecked(state.perItem)
  ui.perItemCheck.onCheckChange = function(_, checked)
    state.perItem = checked
  end
  -- Load, Apply, Save, Clear, Close
  ui.btnLoad.onClick = function()
    -- Fill fields from current offsets
    local dk = getCurrentDirKey()
    local function readOffsets(slotName)
      local p = g_game.getLocalPlayer(); if not p then return {} end
      local itemId = getCurrentItemId(slotName)
      local map, _ = nil, false
      if state.perItem and itemId and _G['paperdoll_set_item_offsets'] then
        -- No direct getter available; leave empty to avoid misleading values
        return {}
      else
        -- defaults not directly exposed; leave empty
        return {}
      end
    end
    -- No-op reader for now; UI fields are for writing primarily
  end
  local function getXY()
    local nX = tonumber(ui.northX:getText()) or 0
    local nY = tonumber(ui.northY:getText()) or 0
    local eX = tonumber(ui.eastX:getText()) or 0
    local eY = tonumber(ui.eastY:getText()) or 0
    local sX = tonumber(ui.southX:getText()) or 0
    local sY = tonumber(ui.southY:getText()) or 0
    local wX = tonumber(ui.westX:getText()) or 0
    local wY = tonumber(ui.westY:getText()) or 0
    local onTop = ui.onTopAll:isChecked()
    return {
      N = { nX, nY, onTop },
      E = { eX, eY, onTop },
      S = { sX, sY, onTop },
      W = { wX, wY, onTop },
    }
  end
  ui.btnApply.onClick = function()
    local map = getXY()
    local slot = state.slot
    if state.perItem then
      local itemId = getCurrentItemId(slot)
      if itemId and paperdoll_set_item_offsets then
        paperdoll_set_item_offsets(slot, itemId, map, true)
      end
    else
      if paperdoll_set_slot_offsets then
        paperdoll_set_slot_offsets(slot, map, true)
      end
    end
  end
  ui.btnSave.onClick = function()
    if _G['savePaperdollOffsets'] then _G['savePaperdollOffsets']() end
  end
  ui.btnClear.onClick = function()
    clearItem()
  end
  ui.btnClose.onClick = function()
    if ui then ui:destroy() ui = nil end
  end
  -- Nudge buttons apply on current facing dir using fields step
  local function bumpBy(dx, dy)
    local dk = getCurrentDirKey()
    nudge(state.slot, dk, dx, dy)
  end
  ui.btnUp.onClick = function() bumpBy(0, -1) end
  ui.btnDown.onClick = function() bumpBy(0, 1) end
  ui.btnLeft.onClick = function() bumpBy(-1, 0) end
  ui.btnRight.onClick = function() bumpBy(1, 0) end
  g_logger.info('[paperdoll] Calibrator pronto. UI aberta e atalhos ativos.')
end

function terminate()
  controller:terminate()
  if ui then ui:destroy() ui = nil end
end
