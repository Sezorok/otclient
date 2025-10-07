modules.game_paperdoll_calibrator = modules.game_paperdoll_calibrator or {}
local M = modules.game_paperdoll_calibrator

local ALL_SLOTS = { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
local USE_ITEM_OFFSETS = false

local function resolveSlotId(slotName)
  if slotName == 'head' then return InventorySlotHead end
  if slotName == 'neck' then return InventorySlotNeck end
  if slotName == 'back' then return InventorySlotBack end
  if slotName == 'body' then return InventorySlotBody end
  if slotName == 'right' then return InventorySlotRight end
  if slotName == 'left' then return InventorySlotLeft end
  if slotName == 'legs' then return InventorySlotLeg end
  if slotName == 'feet' then return InventorySlotFeet end
  if slotName == 'finger' then return InventorySlotFinger end
  if slotName == 'ammo' then return InventorySlotAmmo end
  if slotName == 'purse' then return InventorySlotPurse end
  return nil
end

local function getCurrentDirKey()
  local p = g_game.getLocalPlayer()
  local dir = p and (p.getDirection and p:getDirection() or South) or South
  local map = { [North]='N',[East]='E',[South]='S',[West]='W',[0]='N',[1]='E',[2]='S',[3]='W' }
  return map[dir] or 'S'
end

local function nudgeSlotDefault(slotName, dirKey, dx, dy)
  if not paperdoll_nudge_body then return end -- require overlay API
  if slotName == 'body' then return paperdoll_nudge_body(dirKey, dx, dy) end
  if slotName == 'head' then return paperdoll_nudge_head(dirKey, dx, dy) end
  -- generic fallback via public API
  if paperdoll_nudge_item then
    return paperdoll_nudge_item(slotName, dirKey, dx, dy)
  end
end

-- internal lifecycle (use locals to avoid reload recursion)
local function moduleInit()
  -- optional TopMenu button (only show to GM if available)
  if modules and modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
    pcall(function()
      local btn = modules.game_mainpanel.addToggleButton('paperdollCalibrationButton', tr('Paperdoll Offsets'), '/images/options/hotkeys', function()
        M.open()
      end, false, 1000)
      if btn and btn.setOn then btn:setOn(false) end
    end)
  end
  if g_keyboard and g_keyboard.bindKeyDown then
    g_keyboard.bindKeyDown('Ctrl+Shift+D', function() M.open() end)
  end
end

local function moduleTerminate()
  if M._wnd then M._wnd:destroy(); M._wnd = nil end
end

function M.open()
  if not g_ui or not g_ui.getRootWidget then return end
  local root = g_ui.getRootWidget()
  if M._wnd and M._wnd:isVisible() then M._wnd:raise(); M._wnd:focus(); return end
  local w = (g_ui.displayUI and g_ui.displayUI('paperdoll_calibrator')) or g_ui.loadUI('/game_paperdoll_calibrator/paperdoll_calibrator', root) or g_ui.loadUI('paperdoll_calibrator', root)
  if w then
    w:show(); w:raise(); w:focus()
    M.onCalibratorSetup(w)
  end
  M._wnd = w
end

function M.onCalibratorSetup(w)
  w._slotIndex = 4
  local slotValue = w:recursiveGetChildById('slotValue') or w:getChildById('slotValue')
  if slotValue then slotValue:setText(ALL_SLOTS[w._slotIndex]) end
  local perItem = w:recursiveGetChildById('perItemCheck') or w:getChildById('perItemCheck')
  if perItem then perItem:setChecked(USE_ITEM_OFFSETS) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(ALL_SLOTS[w._slotIndex] or 'body'))) end
  local dirLabel = w:recursiveGetChildById('dirVal') or w:getChildById('dirVal')
  if dirLabel then dirLabel:setText(getCurrentDirKey()) end
end

local function getSelected(w)
  local slot = ALL_SLOTS[w._slotIndex or 4]
  local stepWidget = (w:recursiveGetChildById('stepSpin') or w:getChildById('stepSpin'))
  local step = (stepWidget and (stepWidget.getValue and stepWidget:getValue() or tonumber(stepWidget:getText()))) or 1
  local dirKey = getCurrentDirKey()
  return slot, dirKey, step
end

function M.onAdjustClick(axis, sign)
  local w = M._wnd; if not w then return end
  local slot, dir, step = getSelected(w)
  local dx, dy = 0, 0
  if axis == 'x' then dx = sign * step else dy = sign * step end
  local v
  if USE_ITEM_OFFSETS and paperdoll_nudge_item and paperdoll_get_active_item_id and paperdoll_get_active_item_id(slot) ~= 0 then
    v = paperdoll_nudge_item(slot, dir, dx, dy)
  else
    v = nudgeSlotDefault(slot, dir, dx, dy)
  end
  local vx = (type(v) == 'table' and v[1]) or 0
  local vy = (type(v) == 'table' and v[2]) or 0
  local offLbl = w:recursiveGetChildById('offsetValue') or w:getChildById('offsetValue')
  if offLbl and offLbl.setText then offLbl:setText(string.format('(%d,%d,true)', vx, vy)) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(slot))) end
end

function M.onPerItemToggle(widget, checked)
  USE_ITEM_OFFSETS = not not checked
end

function M.onCloseCalibrator()
  if M._wnd then M._wnd:destroy(); M._wnd = nil end
end

function M.onUseCurrentDir()
  local w = M._wnd; if not w then return end
  local dirLabel = w:recursiveGetChildById('dirVal') or w:getChildById('dirVal')
  if dirLabel then dirLabel:setText(getCurrentDirKey()) end
end

function M.onSaveOffsets()
  if paperdoll_save_offsets then paperdoll_save_offsets() end
end

function M.onClearItem()
  local w = M._wnd; if not w then return end
  local slot = ALL_SLOTS[w._slotIndex or 4]
  if paperdoll_clear_item_offsets then paperdoll_clear_item_offsets(slot) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(slot))) end
end

function M.onResetSlot()
  local w = M._wnd; if not w then return end
  local slot = ALL_SLOTS[w._slotIndex or 4]
  -- Fallback to default maps via console helpers (relies on overlay's API)
  if slot == 'head' and setSlotOffsets then setSlotOffsets('head', { N={31,37,true}, E={32,33,true}, S={33,32,true}, W={35,30,true} }) end
  if slot == 'body' and setSlotOffsets then setSlotOffsets('body', { N={32,34,true}, E={33,33,true}, S={33,34,true}, W={34,31,true} }) end
  if paperdoll_save_offsets then paperdoll_save_offsets() end
end

-- namespace exports for OTUI
M.onCalibratorSetup = M.onCalibratorSetup
M.onAdjustClick = M.onAdjustClick
M.onPerItemToggle = M.onPerItemToggle
M.onCloseCalibrator = M.onCloseCalibrator
M.onUseCurrentDir = M.onUseCurrentDir
M.onSaveOffsets = M.onSaveOffsets
M.onClearItem = M.onClearItem
M.onResetSlot = M.onResetSlot

-- module lifecycle
M.init = moduleInit
M.terminate = moduleTerminate
function init() return moduleInit() end
function terminate() return moduleTerminate() end
