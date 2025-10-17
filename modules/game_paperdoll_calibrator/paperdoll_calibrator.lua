local controller = Controller:new()
local ui = nil

modules.game_paperdoll_calibrator = modules.game_paperdoll_calibrator or {}

local function wireUI(win)
  if not win then return end
  local f = modules.game_paperdoll_overlay
  local function get(id) return win:recursiveGetChildById(id) end
  -- Populate slot options if needed
  local slotBox = get('slotBox')
  if slotBox and slotBox:getOptionsCount() == 0 then
    local slots = { 'head','body','back','left','right','legs','feet','neck','finger','ammo','purse' }
    for _, s in ipairs(slots) do slotBox:addOption(s, s) end
  end
  -- Populate step options
  local stepBox = get('stepBox')
  if stepBox and stepBox:getOptionsCount() == 0 then
    stepBox:addOption('1', 1); stepBox:addOption('2', 2)
    stepBox:addOption('5', 5); stepBox:addOption('10', 10)
  end
  -- Helpers
  local invMap = { head=InventorySlotHead, neck=InventorySlotNeck, back=InventorySlotBack, body=InventorySlotBody,
    right=InventorySlotRight, left=InventorySlotLeft, legs=InventorySlotLeg, feet=InventorySlotFeet,
    finger=InventorySlotFinger, ammo=InventorySlotAmmo, purse=InventorySlotPurse }
  local function currentSlot()
    local o = slotBox and slotBox:getCurrentOption()
    local s = (o and (o.data or o.text)) or 'body'
    return tostring(s):lower()
  end
  local function readMap()
    local function gv(id) local e=get(id); return tonumber(e and e:getText() or '0') or 0 end
    local onTop = (get('onTopAll') and get('onTopAll'):isChecked()) or false
    return { N={gv('northX'),gv('northY'),onTop}, E={gv('eastX'),gv('eastY'),onTop}, S={gv('southX'),gv('southY'),onTop}, W={gv('westX'),gv('westY'),onTop} }
  end
  -- Button handlers
  local btnApply, btnSave, btnClear, btnClose = get('btnApply'), get('btnSave'), get('btnClear'), get('btnClose')
  if btnApply then
    btnApply.onClick = function()
      local slot = currentSlot()
      local perItem = (get('perItemCheck') and get('perItemCheck'):isChecked()) or false
      local map = readMap()
      if perItem then
        local p = g_game.getLocalPlayer(); local it = p and p:getInventoryItem(invMap[slot])
        if it and f and f.paperdoll_set_item_offsets then f.paperdoll_set_item_offsets(slot, it:getId(), map, true) end
      else
        if f and f.paperdoll_set_slot_offsets then f.paperdoll_set_slot_offsets(slot, map, true) end
      end
    end
  end
  if btnSave then btnSave.onClick = function() if _G.savePaperdollOffsets then _G.savePaperdollOffsets() end end end
  if btnClear then
    btnClear.onClick = function()
      local slot = currentSlot()
      local p = g_game.getLocalPlayer(); local it = p and p:getInventoryItem(invMap[slot])
      if it and f and f.paperdoll_clear_item_offsets then f.paperdoll_clear_item_offsets(slot, it:getId()) end
    end
  end
  if btnClose then btnClose.onClick = function() win:destroy() end end
end

function modules.game_paperdoll_calibrator.openUI()
  -- Try by name first (module-relative), fallback to absolute path
  local ok, win = pcall(function() return g_ui.displayUI('paperdoll_calibrator') end)
  if not (ok and win) then
    g_ui.importStyle('/game_paperdoll_calibrator/paperdoll_calibrator.otui')
    ok, win = pcall(function() return g_ui.loadUI('/game_paperdoll_calibrator/paperdoll_calibrator.otui', rootWidget) end)
  end
  if ok and win then
    ui = win
    wireUI(ui)
    return ui
  end
  g_logger.warning('[paperdoll] Falha ao abrir UI do calibrador.')
  return nil
end

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
  -- Try open UI; continue headless if it fails
  if not modules.game_paperdoll_calibrator.openUI() then
    g_logger.warning('[paperdoll] Calibrator em modo headless (use comandos/atalhos).')
  end
end

function terminate()
  controller:terminate()
  if ui then ui:destroy() ui = nil end
end
