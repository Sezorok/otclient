local wnd

local function isAllowed()
  local p = g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  local isGm = (g_game.isGM and g_game.isGM()) or false
  local groupId = p and p.getGroup and p:getGroup() or nil
  local accountType = p and p.getAccountType and p:getAccountType() or nil
  local gmActions = (g_game.getGMActions and g_game.getGMActions()) or nil
  local gmActionsHasAny = (type(gmActions) == 'table' and next(gmActions) ~= nil)
  local allowed = isGm or gmActionsHasAny or (type(groupId) == 'number' and groupId >= 6) or (type(accountType) == 'number' and accountType >= 5)
  print(string.format('[Calibrator] god status check: %s', allowed and 'true' or 'false'))
  print(string.format('[Calibrator] perms: isGM=%s, GMActions=%s, group=%s, accountType=%s', isGm and 'true' or 'false', gmActionsHasAny and 'true' or 'false', tostring(groupId), tostring(accountType)))
  return allowed
end

function init()
  -- add button in TopMenu (available to all; access checked on open)
  modules.game_mainpanel.addToggleButton('paperdollCalibrationButton', tr('Paperdoll Offsets'), '/images/options/hotkeys', function()
    modules.game_paperdoll_calibrator.open()
  end, false, 1000)
  if g_keyboard and g_keyboard.bindKeyDown then
    g_keyboard.bindKeyDown('Ctrl+Shift+D', function() modules.game_paperdoll_calibrator.open() end)
  end
end

function terminate()
  if wnd then wnd:destroy(); wnd = nil end
end

local function updateArrowsEnabled(w)
  local slot = w._allSlots[w._slotIndex or 4]
  local slotId = modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.resolveSlotId and modules.game_paperdoll_overlay.resolveSlotId(slot) or nil
  local has = false
  local p = g_game.getLocalPlayer()
  if p and slotId and p.getInventoryItem then
    local it = p:getInventoryItem(slotId)
    if it and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.findDirectionalPNGs then
      local paths = modules.game_paperdoll_overlay.findDirectionalPNGs(slotId, it:getId())
      has = (paths and next(paths) ~= nil)
    end
  end
  for _, bid in ipairs({ 'btnLeft','btnRight','btnUp','btnDown' }) do
    local b = w:recursiveGetChildById(bid) or w:getChildById(bid)
    if b and b.setEnabled then b:setEnabled(has) end
  end
end

local function onSetup(w)
  w._slotIndex = 4
  w._allSlots = { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
  w:recursiveGetChildById('slotValue'):setText(w._allSlots[w._slotIndex])
  local perItem = w:recursiveGetChildById('perItemCheck')
  if perItem then perItem:setChecked(false) end
  local idLbl = w:recursiveGetChildById('itemIdLabel')
  if idLbl and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_get_active_item_id then
    idLbl:setText(string.format('Item: %d', modules.game_paperdoll_overlay.paperdoll_get_active_item_id(w._allSlots[w._slotIndex] or 'body')))
  end
  updateArrowsEnabled(w)
  local dirLabel = w:recursiveGetChildById('dirVal')
  if dirLabel and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_get_current_dir_key then
    dirLabel:setText(modules.game_paperdoll_overlay.paperdoll_get_current_dir_key())
  end
end

local function doNudge(slot, dir, dx, dy, perItem)
  if not modules.game_paperdoll_overlay then return end
  if perItem and modules.game_paperdoll_overlay.paperdoll_nudge_item then
    return modules.game_paperdoll_overlay.paperdoll_nudge_item(slot, dir, dx, dy)
  end
  if slot == 'head' and modules.game_paperdoll_overlay.paperdoll_nudge_head then
    return modules.game_paperdoll_overlay.paperdoll_nudge_head(dir, dx, dy)
  end
  if slot == 'body' and modules.game_paperdoll_overlay.paperdoll_nudge_body then
    return modules.game_paperdoll_overlay.paperdoll_nudge_body(dir, dx, dy)
  end
  -- generic per-slot default nudge via slot API if available
  if modules.game_paperdoll_overlay.paperdoll_nudge_slot then
    return modules.game_paperdoll_overlay.paperdoll_nudge_slot(slot, dir, dx, dy)
  end
end

local function onAdjust(axis, sign)
  if not wnd then return end
  local slot = wnd._allSlots[wnd._slotIndex or 4]
  local stepWidget = wnd:recursiveGetChildById('stepSpin')
  local step = (stepWidget and (stepWidget.getValue and stepWidget:getValue() or tonumber(stepWidget:getText()))) or 1
  local dir = (modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_get_current_dir_key and modules.game_paperdoll_overlay.paperdoll_get_current_dir_key()) or 'S'
  local perItem = (wnd:recursiveGetChildById('perItemCheck') and wnd:recursiveGetChildById('perItemCheck'):isChecked()) or false
  local dx, dy = 0, 0
  if axis == 'x' then dx = sign * step else dy = sign * step end
  local v = doNudge(slot, dir, dx, dy, perItem)
  local vx = (type(v) == 'table' and v[1]) or 0
  local vy = (type(v) == 'table' and v[2]) or 0
  local offLbl = wnd:recursiveGetChildById('offsetValue')
  if offLbl and offLbl.setText then offLbl:setText(string.format('(%d,%d,true)', vx, vy)) end
  local idLbl = wnd:recursiveGetChildById('itemIdLabel')
  if idLbl and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_get_active_item_id then
    idLbl:setText(string.format('Item: %d', modules.game_paperdoll_overlay.paperdoll_get_active_item_id(slot)))
  end
end

modules.game_paperdoll_calibrator = {}

function modules.game_paperdoll_calibrator.open()
  if not isAllowed() then
    print('[Calibrator] access denied: Calibrator is restricted to GM accounts.')
    return
  end
  if wnd and wnd:isVisible() then wnd:raise(); wnd:focus(); return end
  wnd = g_ui.displayUI('paperdoll_calibrator') or g_ui.loadUI('/game_paperdoll_calibrator/paperdoll_calibrator')
  if not wnd then print('[Calibrator] failed to load UI window'); return end
  wnd:show(); wnd:raise(); wnd:focus()
  onSetup(wnd)
end

function modules.game_paperdoll_calibrator.onSetup(self) onSetup(self) end
function modules.game_paperdoll_calibrator.onAdjust(axis, sign) onAdjust(axis, sign) end
function modules.game_paperdoll_calibrator.onSlotPrev()
  if not wnd then return end
  wnd._slotIndex = math.max(1, (wnd._slotIndex or 4) - 1)
  wnd:recursiveGetChildById('slotValue'):setText(wnd._allSlots[wnd._slotIndex])
  updateArrowsEnabled(wnd)
end
function modules.game_paperdoll_calibrator.onSlotNext()
  if not wnd then return end
  wnd._slotIndex = math.min(#wnd._allSlots, (wnd._slotIndex or 4) + 1)
  wnd:recursiveGetChildById('slotValue'):setText(wnd._allSlots[wnd._slotIndex])
  updateArrowsEnabled(wnd)
end
function modules.game_paperdoll_calibrator.onUseCurrentDir()
  if not wnd then return end
  local dirLabel = wnd:recursiveGetChildById('dirVal')
  if dirLabel and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_get_current_dir_key then
    dirLabel:setText(modules.game_paperdoll_overlay.paperdoll_get_current_dir_key())
  end
end
function modules.game_paperdoll_calibrator.onSaveOffsets()
  if modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_save_offsets then
    modules.game_paperdoll_overlay.paperdoll_save_offsets()
  end
end
function modules.game_paperdoll_calibrator.onClearItem()
  if not wnd then return end
  local slot = wnd._allSlots[wnd._slotIndex or 4]
  if modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_clear_item_offsets then
    modules.game_paperdoll_overlay.paperdoll_clear_item_offsets(slot)
  end
end
function modules.game_paperdoll_calibrator.onResetSlot()
  if not wnd then return end
  local slot = wnd._allSlots[wnd._slotIndex or 4]
  if modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.setSlotOffsets and modules.game_paperdoll_overlay.makeDefaultForSlot then
    local defaults = modules.game_paperdoll_overlay.makeDefaultForSlot(slot)
    modules.game_paperdoll_overlay.setSlotOffsets(slot, defaults)
    modules.game_paperdoll_overlay.paperdoll_save_offsets()
  end
end
function modules.game_paperdoll_calibrator.onExport()
  if not wnd then return end
  local slot = wnd._allSlots[wnd._slotIndex or 4]
  if modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.paperdoll_print_current_dir then
    modules.game_paperdoll_overlay.paperdoll_print_current_dir()
  end
end
