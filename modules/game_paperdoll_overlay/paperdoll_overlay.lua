local SLOT_DIR = {
  [InventorySlotHead]   = "head",
  [InventorySlotNeck]   = "neck",
  [InventorySlotBack]   = "back",
  [InventorySlotBody]   = "body",
  [InventorySlotRight]  = "right",
  [InventorySlotLeft]   = "left",
  [InventorySlotLeg]    = "legs",
  [InventorySlotFeet]   = "feet",
  [InventorySlotFinger] = "finger",
  [InventorySlotAmmo]   = "ammo",
  [InventorySlotPurse]  = "purse",
}

local SLOT_BASE = {
  [InventorySlotHead]   = 10000,
  [InventorySlotNeck]   = 20000,
  [InventorySlotBack]   = 30000,
  [InventorySlotBody]   = 40000,
  [InventorySlotRight]  = 50000,
  [InventorySlotLeft]   = 60000,
  [InventorySlotLeg]    = 70000,
  [InventorySlotFeet]   = 80000,
  [InventorySlotFinger] = 90000,
  [InventorySlotAmmo]   = 100000,
  [InventorySlotPurse]  = 110000,
}

local DIR_INDEX = { [North] = 0, [East] = 1, [South] = 2, [West] = 3 }
local INDEX_TO_DIR = { North, East, South, West }

local function applyDefaultOffsets(eff)
  eff:setDirOffset(North, 0, -6, true)
  eff:setDirOffset(East,  6, -4, true)
  eff:setDirOffset(South, 0,  8, true)
  eff:setDirOffset(West, -6, -4, true)
end

local state = { current = {}, activeEffect = {} }
-- must be defined before functions to be captured as upvalue
local invisByCreature = {}
-- Calibration config
local USE_ITEM_OFFSETS = false -- default: slot-level calibration only

-- Runtime-configurable offsets (persisted under /settings/paperdoll_offsets.json)
local OFFSETS = nil
local OFFSETS_PATH = "/settings/paperdoll_offsets.json"
local DIR_ALIAS = { N = North, E = East, S = South, W = West }
-- Ensure both enum constants and raw numeric directions resolve
local DIR_TO_KEY = { [North] = 'N', [East] = 'E', [South] = 'S', [West] = 'W', [0]='N', [1]='E', [2]='S', [3]='W', [NorthEast]='E', [SouthEast]='E', [SouthWest]='W', [NorthWest]='W', [4]='E', [5]='E', [6]='W', [7]='W' }

local function resolveDirIdxForEffect(dir)
  local idx = DIR_INDEX[dir]
  if idx ~= nil then return idx end
  -- map diagonals to nearest cardinal (horizontal preference to reduce S fallback)
  if dir == NorthEast or dir == SouthEast or dir == 4 or dir == 5 then return DIR_INDEX[East] end
  if dir == SouthWest or dir == NorthWest or dir == 6 or dir == 7 then return DIR_INDEX[West] end
  return DIR_INDEX[South] -- safe fallback
end

local function loadOffsets()
  if OFFSETS then return OFFSETS end
  if g_resources.fileExists(OFFSETS_PATH) then
    local ok, data = pcall(function() return json.decode(g_resources.readFileContents(OFFSETS_PATH)) end)
    if ok and type(data) == 'table' then OFFSETS = data end
  end
  if not OFFSETS then
    OFFSETS = {
      head = { default = { N = {31,37,true}, E = {32,33,true}, S = {33,32,true}, W = {35,30,true} } },
      body = { default = { N = {32,34,true}, E = {33,33,true}, S = {33,34,true}, W = {34,31,true} } },
    }
  end
  return OFFSETS
end

local function saveOffsets()
  if not OFFSETS then return end
  local ok, data = pcall(function() return json.encode(OFFSETS, 2) end)
  if ok then g_resources.writeFileContents(OFFSETS_PATH, data) end
end

local function getSlotName(slot)
  return SLOT_DIR[slot]
end

local function getOffsetsFor(slot, itemId)
  local slotName = getSlotName(slot)
  local conf = loadOffsets()[slotName]
  if not conf then return nil end
  if USE_ITEM_OFFSETS and itemId and conf.items and conf.items[tostring(itemId)] then
    return conf.items[tostring(itemId)], true
  end
  return conf.default, false
end

-- Resolve slot name to InventorySlot id
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

local function applyOffsetsForAllDirs(eff, slot, itemId)
  local map = getOffsetsFor(slot, itemId)
  if not map then applyDefaultOffsets(eff); return end
  local function avg(a, b)
    if not a and not b then return {0,0,true} end
    if not a then return { b[1] or 0, b[2] or 0, b[3] and true or false } end
    if not b then return { a[1] or 0, a[2] or 0, a[3] and true or false } end
    return { math.floor(((a[1] or 0) + (b[1] or 0)) / 2), math.floor(((a[2] or 0) + (b[2] or 0)) / 2), (a[3] and true) or (b[3] and true) or false }
  end
  local function applyDir(dirKey)
    local v = map[dirKey]
    if v then eff:setDirOffset(DIR_ALIAS[dirKey], v[1] or 0, v[2] or 0, v[3] and true or false) end
  end
  applyDir('N'); applyDir('E'); applyDir('S'); applyDir('W')
  -- set diagonal offsets as blended between adjacent cardinals
  local vNE = avg(map.N, map.E)
  local vSE = avg(map.S, map.E)
  local vSW = avg(map.S, map.W)
  local vNW = avg(map.N, map.W)
  eff:setDirOffset(NorthEast, vNE[1] or 0, vNE[2] or 0, vNE[3] and true or false)
  eff:setDirOffset(SouthEast, vSE[1] or 0, vSE[2] or 0, vSE[3] and true or false)
  eff:setDirOffset(SouthWest, vSW[1] or 0, vSW[2] or 0, vSW[3] and true or false)
  eff:setDirOffset(NorthWest, vNW[1] or 0, vNW[2] or 0, vNW[3] and true or false)
end

local function applyOffsetsToActive(slot)
  local p = g_game.getLocalPlayer()
  if not p then return end
  local activeId = state.activeEffect[slot]
  if not activeId then return end
  local eff = p.getAttachedEffectById and p:getAttachedEffectById(activeId)
  if not eff then return end
  local item = p:getInventoryItem(slot)
  local itemId = item and item:getId() or 0
  applyOffsetsForAllDirs(eff, slot, itemId)
  local dir = p.getDirection and p:getDirection() or South
  local dirResolved = INDEX_TO_DIR[resolveDirIdxForEffect(dir)] or South
  if eff.setDirection then eff:setDirection(dirResolved) end
end

local function makeEffectId(slot, itemId, dirIdx)
  return SLOT_BASE[slot] + (itemId % 10000) + (dirIdx or 0)
end

local BASE_DIRS = { "/images/paperdll/", "/images/paperdoll/" } -- support both spellings

local function findDirectionalPNGs(slot, itemId)
  local dirName = SLOT_DIR[slot]
  if not dirName then return {} end
  local map = {}
  for _, baseDir in ipairs(BASE_DIRS) do
    local any = false
    for i = 0, 3 do
      local path = string.format("%s%s/%d_%d.png", baseDir, dirName, itemId, i)
      if g_resources.fileExists(path) then map[i] = path; any = true end
    end
    if any then return map end
  end
  return map
end

local WALK_BOUNCE = false
local BOUNCE_PARAMS = { 0, 6, 800 }

local function buildEffectConfig(slot, itemId)
  local cfg = { onTop = true, dirOffset = {} }
  if WALK_BOUNCE then
    cfg.bounce = { BOUNCE_PARAMS[1], BOUNCE_PARAMS[2], BOUNCE_PARAMS[3] }
  end
  local map = getOffsetsFor(slot, itemId)
  if map then
    if map.N then cfg.dirOffset[North] = { map.N[1] or 0, map.N[2] or 0, map.N[3] and true or false } end
    if map.E then cfg.dirOffset[East]  = { map.E[1] or 0, map.E[2] or 0, map.E[3] and true or false } end
    if map.S then cfg.dirOffset[South] = { map.S[1] or 0, map.S[2] or 0, map.S[3] and true or false } end
    if map.W then cfg.dirOffset[West]  = { map.W[1] or 0, map.W[2] or 0, map.W[3] and true or false } end
  else
    -- fallback to defaults
    cfg.dirOffset[North] = { 0, -6, true }
    cfg.dirOffset[East]  = { 6, -4, true }
    cfg.dirOffset[South] = { 0,  8, true }
    cfg.dirOffset[West]  = { -6, -4, true }
  end
  return cfg
end

local function updateManagerConfigFor(slot, itemId)
  if not AttachedEffectManager or not AttachedEffectManager.get then return end
  local map = getOffsetsFor(slot, itemId) or {}
  for i = 0, 3 do
    local effId = makeEffectId(slot, itemId, i)
    local def = AttachedEffectManager.get(effId)
    if def then
      def.config = def.config or {}
      def.config.onTop = true
      def.config.dirOffset = def.config.dirOffset or {}
      local function put(dirConst, key)
        local v = map[key]
        if v then def.config.dirOffset[dirConst] = { v[1] or 0, v[2] or 0, v[3] and true or false } end
      end
      put(North,'N'); put(East,'E'); put(South,'S'); put(West,'W')
    end
  end
end

local function ensureEffects(slot, itemId, dirPaths)
  for i = 0, 3 do
    local path = dirPaths[i]
    if path then
      local effId = makeEffectId(slot, itemId, i)
      -- Prefer manager if available; fallback to direct registration
      if AttachedEffectManager and AttachedEffectManager.get and not AttachedEffectManager.get(effId) then
        AttachedEffectManager.register(effId, "paperdll", path, ThingExternalTexture, buildEffectConfig(slot, itemId))
      elseif not g_attachedEffects.getById(effId) then
        g_attachedEffects.registerByImage(effId, "paperdll", path, true)
        local eff = g_attachedEffects.getById(effId)
        if eff then
          eff:setOnTop(true)
          applyOffsetsForAllDirs(eff, slot, itemId)
        end
      end
    end
  end
end

local function switchDirEffect(player, slot, itemId, dirIdx, dirPaths, forceRestart, effectDir)
  local wantedEffId = makeEffectId(slot, itemId, dirIdx)
  if not dirPaths[dirIdx] then
    -- remap diagonals or missing dirs to nearest horizontal first, then south as fallback
    local mappedIdx = resolveDirIdxForEffect(INDEX_TO_DIR[dirIdx] or dirIdx)
    if dirPaths[mappedIdx] then
      wantedEffId = makeEffectId(slot, itemId, mappedIdx)
    elseif dirPaths[2] then
      wantedEffId = makeEffectId(slot, itemId, 2)
    else
      for i = 0, 3 do if dirPaths[i] then wantedEffId = makeEffectId(slot, itemId, i); break end end
    end
  end
  local active = state.activeEffect[slot]
  if forceRestart or (active and active ~= wantedEffId) or (player.getAttachedEffectById and not player:getAttachedEffectById(wantedEffId)) then
    local eff = g_attachedEffects.getById(wantedEffId)
    if eff then
      -- Apply latest offsets at attach time so runtime changes take effect
      applyOffsetsForAllDirs(eff, slot, itemId)
      -- Ensure effect respects current facing direction for dir-specific offsets
      local dirConst = effectDir or (INDEX_TO_DIR[dirIdx] or South)
      if eff.setDirection then eff:setDirection(dirConst) end
      -- attach new first to avoid visual gap, then detach old if needed
      player:attachEffect(eff)
      if active and active ~= wantedEffId and player.detachEffectById then
        player:detachEffectById(active)
      end
      state.activeEffect[slot] = wantedEffId
    end
  else
    state.activeEffect[slot] = wantedEffId
  end
end

local function updateSlotOverlay(player, slot, item)
  if not slot then return end
  -- Do not (re)attach overlays while invisible
  local cid = player.getId and player:getId() or nil
  if cid and invisByCreature[cid] then
    if state.activeEffect[slot] then
      if player.detachEffectById then
        player:detachEffectById(state.activeEffect[slot])
      end
      state.activeEffect[slot] = nil
    end
    state.current[slot] = nil
    return
  end
  if not item then
    if state.activeEffect[slot] then
      if player.detachEffectById then
        player:detachEffectById(state.activeEffect[slot])
      end
      state.activeEffect[slot] = nil
    end
    state.current[slot] = nil
    return
  end

  local itemId = item:getId()
  state.current[slot] = itemId

  local dirPaths = findDirectionalPNGs(slot, itemId)
  if next(dirPaths) == nil then
    -- no images for this item/slot, ensure we detach any previous overlay
    if state.activeEffect[slot] then
      if player.detachEffectById then
        player:detachEffectById(state.activeEffect[slot])
      end
      state.activeEffect[slot] = nil
    end
    return
  end
  ensureEffects(slot, itemId, dirPaths)

  local dir = player.getDirection and player:getDirection() or South
  local dirIdx = DIR_INDEX[dir] or 2
  switchDirEffect(player, slot, itemId, dirIdx, dirPaths)
end

local controller = Controller:new()
local lastDirIdx = nil
local cycleName = "paperdoll_dir"

local function isInvisible(outfit)
  -- Protocol sets invisible as: lookType=0 and lookTypeEx=0 -> auxType=13 (effect id)
  return outfit and outfit.type == 0 and outfit.auxType == 13
end

local function detachAllOverlays(player)
  for _, effId in pairs(state.activeEffect) do
    if effId and player:getAttachedEffectById(effId) then
      player:detachEffectById(effId)
    end
  end
  state.activeEffect = {}
end

-- Module lifecycle wrappers to match .otmod hooks
function init()
  controller:init()
  -- ensure manager module is available for effect configs
  if g_modules and g_modules.ensureModuleLoaded then
    g_modules.ensureModuleLoaded('game_attachedeffects')
  end

  -- Register developer button and hotkey non-intrusively once the game starts
  controller:registerEvents(g_game, {
    onGameStart = function()
      -- Log GM/God status; button shown to all, access checked on open
      print(string.format('[Calibrator] god status check: %s', isCalibratorAllowed() and 'true' or 'false'))
      pcall(function()
        if modules and modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
          local btn = modules.game_mainpanel.addToggleButton(
            'paperdollCalibrationButton',
            tr('Paperdoll Offsets'),
            '/images/options/hotkeys',
            function()
              if modules and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.openPaperdollCalibrator then
                modules.game_paperdoll_overlay.openPaperdollCalibrator()
              end
            end,
            false,
            1000
          )
          if btn and btn.setOn then btn:setOn(false) end
        end
      end)
      pcall(function()
        if g_keyboard and g_keyboard.bindKeyDown then
          g_keyboard.bindKeyDown('Ctrl+Shift+D', function() openPaperdollCalibrator() end)
        end
      end)
    end
  }):execute()

  -- Pre-register available paperdoll textures to avoid on-demand errors
  local slotDirs = { "head", "body", "back", "left", "right", "legs", "feet", "neck", "finger", "ammo", "purse" }
  for _, baseDir in ipairs(BASE_DIRS) do
    for _, dir in ipairs(slotDirs) do
      local realDir = g_resources.getRealDir(baseDir .. dir)
      if realDir and g_resources.directoryExists(realDir) then
        for _, file in ipairs(g_resources.getDirectoryFiles(realDir)) do
          if file:match("_%d+%.png$") then
            local id = tonumber(file:match("^(%d+)_"))
            if id then
              for i = 0, 3 do
                local path = string.format("%s%s/%d_%d.png", baseDir, dir, id, i)
                if g_resources.fileExists(path) then
                  local slot
                  for k, name in pairs(SLOT_DIR) do if name == dir then slot = k break end end
                  if slot then
                    local effId = makeEffectId(slot, id, i)
                    if AttachedEffectManager and AttachedEffectManager.get and not AttachedEffectManager.get(effId) then
                      AttachedEffectManager.register(effId, "paperdll", path, ThingExternalTexture, buildEffectConfig(slot, id))
                    elseif not g_attachedEffects.getById(effId) then
                      g_attachedEffects.registerByImage(effId, "paperdll", path, true)
                      local eff = g_attachedEffects.getById(effId)
                      if eff then
                        eff:setOnTop(true)
                        applyOffsetsForAllDirs(eff, slot, id)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- Console helpers
function setSlotOffsets(slotName, map)
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].default = map
  -- live apply if current slot matches
  if slotName == 'head' then applyOffsetsToActive(InventorySlotHead) end
  if slotName == 'body' then applyOffsetsToActive(InventorySlotBody) end
  local p = g_game.getLocalPlayer()
  if p then
    local slot = slotName == 'head' and InventorySlotHead or slotName == 'body' and InventorySlotBody or nil
    if slot then
      local it = p:getInventoryItem(slot)
      if it then updateManagerConfigFor(slot, it:getId()) end
    end
  end
end

function setItemOffsets(slotName, itemId, map)
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].items = OFFSETS[slotName].items or {}
  OFFSETS[slotName].items[tostring(itemId)] = map
  if slotName == 'head' then applyOffsetsToActive(InventorySlotHead) end
  if slotName == 'body' then applyOffsetsToActive(InventorySlotBody) end
  local slot = slotName == 'head' and InventorySlotHead or slotName == 'body' and InventorySlotBody or nil
  if slot then updateManagerConfigFor(slot, itemId) end
end

function savePaperdollOffsets()
  saveOffsets()
end

-- Legacy-like console helpers for fine tuning
local function normalizeDirKey(k)
  if type(k) ~= 'string' or #k == 0 then return 'S' end
  local c = k:sub(1,1):upper()
  if c == 'N' or c == 'E' or c == 'S' or c == 'W' then return c end
  return 'S'
end

local function nudgeSlotDefault(slotName, dirKey, dx, dy)
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].default = OFFSETS[slotName].default or {}
  local dk = normalizeDirKey(dirKey)
  local v = OFFSETS[slotName].default[dk] or { 0, 0, true }
  -- screen-based nudge: +x => right, +y => down; stored offsets are subtracted at draw
  v[1] = (v[1] or 0) - (dx or 0)
  v[2] = (v[2] or 0) - (dy or 0)
  OFFSETS[slotName].default[dk] = v
  return v
end

local function nudgeSlotItem(slotName, itemId, dirKey, dx, dy)
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].items = OFFSETS[slotName].items or {}
  local dk = normalizeDirKey(dirKey)
  local key = tostring(itemId)
  OFFSETS[slotName].items[key] = OFFSETS[slotName].items[key] or {}
  local v = OFFSETS[slotName].items[key][dk] or { 0, 0, true }
  -- screen-based nudge: +x => right, +y => down; stored offsets are subtracted at draw
  v[1] = (v[1] or 0) - (dx or 0)
  v[2] = (v[2] or 0) - (dy or 0)
  OFFSETS[slotName].items[key][dk] = v
  return v
end

local function printSlotItem(slotName, itemId)
  loadOffsets()
  local key = tostring(itemId)
  local m = (OFFSETS[slotName] and OFFSETS[slotName].items and OFFSETS[slotName].items[key]) or {}
  local function fmt(k)
    local v = m[k] or {0,0,true}
    return string.format("%s=(%d,%d,%s)", k, v[1] or 0, v[2] or 0, v[3] and 'true' or 'false')
  end
  print(string.format("%s item %d offsets: %s %s %s %s", slotName:gsub('^%l', string.upper), itemId, fmt('N'), fmt('E'), fmt('S'), fmt('W')))
end

local function printSlotDefault(slotName)
  loadOffsets()
  local m = (OFFSETS[slotName] and OFFSETS[slotName].default) or {}
  local function fmt(k)
    local v = m[k] or {0,0,true}
    return string.format("%s=(%d,%d,%s)", k, v[1] or 0, v[2] or 0, v[3] and 'true' or 'false')
  end
  print(string.format("%s offsets: %s %s %s %s", slotName:gsub('^%l', string.upper), fmt('N'), fmt('E'), fmt('S'), fmt('W')))
end

function paperdoll_nudge_body(dirKey, dx, dy)
  local v = nudgeSlotDefault('body', dirKey, dx, dy)
  saveOffsets()
  -- force refresh current attachments to reflect live changes
  local p = g_game.getLocalPlayer()
  if p then
  local dir = p.getDirection and p:getDirection() or South
  local dirIdx = resolveDirIdxForEffect(dir)
    -- re-apply offsets directly to active effect to avoid manager resets
    applyOffsetsToActive(InventorySlotBody)
    local item = p:getInventoryItem(InventorySlotBody)
    if item then
      local paths = findDirectionalPNGs(InventorySlotBody, item:getId())
      if next(paths) ~= nil then
        switchDirEffect(p, InventorySlotBody, item:getId(), dirIdx, paths, true)
      end
    end
  end
  return v
end

function paperdoll_print_body_offsets()
  printSlotDefault('body')
end

function paperdoll_nudge_head(dirKey, dx, dy)
  local v = nudgeSlotDefault('head', dirKey, dx, dy)
  saveOffsets()
  local p = g_game.getLocalPlayer()
  if p then
  local dir = p.getDirection and p:getDirection() or South
  local dirIdx = resolveDirIdxForEffect(dir)
    applyOffsetsToActive(InventorySlotHead)
    local item = p:getInventoryItem(InventorySlotHead)
    if item then
      local paths = findDirectionalPNGs(InventorySlotHead, item:getId())
      if next(paths) ~= nil then
        switchDirEffect(p, InventorySlotHead, item:getId(), dirIdx, paths, true)
      end
    end
  end
  return v
end

function paperdoll_print_head_offsets()
  printSlotDefault('head')
end

-- Convenience: nudge according to current facing direction
local function getCurrentDirKey()
  local p = g_game.getLocalPlayer()
  local dir = p and (p.getDirection and p:getDirection() or South) or South
  return DIR_TO_KEY[dir] or 'S'
end

function paperdoll_nudge_body_current(dx, dy)
  local dk = getCurrentDirKey()
  return paperdoll_nudge_body(dk, dx, dy)
end

function paperdoll_nudge_head_current(dx, dy)
  local dk = getCurrentDirKey()
  return paperdoll_nudge_head(dk, dx, dy)
end

function paperdoll_print_current_dir()
  local p = g_game.getLocalPlayer()
  local dir = p and (p.getDirection and p:getDirection() or South) or South
  print('current dir:', dir, 'key=', getCurrentDirKey())
end

-- Item-specific calibration helpers
function paperdoll_nudge_body_item(dirKey, dx, dy)
  local p = g_game.getLocalPlayer(); if not p then return end
  local it = p:getInventoryItem(InventorySlotBody); if not it then return end
  local v = nudgeSlotItem('body', it:getId(), dirKey, dx, dy)
  saveOffsets(); updateManagerConfigFor(InventorySlotBody, it:getId()); applyOffsetsToActive(InventorySlotBody)
  return v
end

function paperdoll_print_body_item_offsets()
  local p = g_game.getLocalPlayer(); if not p then return end
  local it = p:getInventoryItem(InventorySlotBody); if not it then return end
  printSlotItem('body', it:getId())
end

function paperdoll_clear_body_item_offsets()
  loadOffsets()
  local p = g_game.getLocalPlayer(); if not p then return end
  local it = p:getInventoryItem(InventorySlotBody); if not it then return end
  local key = tostring(it:getId())
  if OFFSETS.body and OFFSETS.body.items then OFFSETS.body.items[key] = nil end
  saveOffsets(); updateManagerConfigFor(InventorySlotBody, it:getId()); applyOffsetsToActive(InventorySlotBody)
end

function controller:onGameStart()
  self:registerEvents(LocalPlayer, {
    onInventoryChange = function(player, slot, item, oldItem)
      updateSlotOverlay(player, slot, item)
    end
    ,
    onOutfitChange = function(creature, outfit)
      -- LocalPlayer-only overlay management; other creatures handled by server effects
      local lp = g_game.getLocalPlayer()
      if not lp or creature ~= lp then return end
      local inv = isInvisible(outfit)
      local cid = creature:getId()
      if inv and not invisByCreature[cid] then
        detachAllOverlays(creature)
        invisByCreature[cid] = true
        return
      end
      if not inv and invisByCreature[cid] then
        for s = InventorySlotFirst, InventorySlotLast do
          updateSlotOverlay(creature, s, creature:getInventoryItem(s))
        end
        invisByCreature[cid] = false
      end
    end
  }):execute()

  local p = g_game.getLocalPlayer()
  if p then
    -- Guard against inconsistent slot bounds on some protocols
    local first = InventorySlotFirst or 1
    local last  = InventorySlotLast or InventorySlotPurse or 11
    for s = first, last do
      updateSlotOverlay(p, s, p:getInventoryItem(s))
    end
    -- React to manual walk start to keep overlays aligned while walking
    self:registerEvents(g_game, {
      onWalk = function(_direction)
        local cid = p.getId and p:getId() or nil
        if cid and invisByCreature[cid] then return end
        -- Use creature facing (cardinal), ignore diagonal params
        local dir = p.getDirection and p:getDirection() or South
        local dirIdx = resolveDirIdxForEffect(dir)
        -- keep overlays aligned without reattach to avoid flicker/jumps
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths, false, dir)
          end
        end
      end,
      onAutoWalk = function(player, dirs)
        local cid = p.getId and p:getId() or nil
        if cid and invisByCreature[cid] then return end
        local dir = p.getDirection and p:getDirection() or South
        local dirIdx = resolveDirIdxForEffect(dir)
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths, false, dir)
          end
        end
      end
    }):execute()
    self:cycleEvent(function()
      if not g_game.isOnline() then return end
      local cid = p.getId and p:getId() or nil
      if cid and invisByCreature[cid] then
        -- While invisible, skip direction switches and inventory re-attach attempts
        return
      end
      -- Continuously apply latest offsets to all active overlays to reflect live tweaks
      for s, _ in pairs(state.current) do applyOffsetsToActive(s) end
      local dir = p.getDirection and p:getDirection() or South
      local dirIdx = resolveDirIdxForEffect(dir)
      if dirIdx ~= lastDirIdx then
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths, false)
          end
        end
        lastDirIdx = dirIdx
      end
      -- Inventory sync: ensure overlays attach/detach even if onInventoryChange isn't fired
      for s = first, last do
        local it = p:getInventoryItem(s)
        local curr = state.current[s]
        local currId = curr
        local itId = it and it:getId() or nil
        if itId ~= currId then
          updateSlotOverlay(p, s, it)
        end
      end
    end, 100, cycleName)
  end
end

function controller:onGameEnd()
  local p = g_game.getLocalPlayer()
  if p then
    for s, effId in pairs(state.activeEffect) do
      if effId then p:detachEffectById(effId) end
    end
  end
  state.activeEffect = {}
  state.current = {}
end

function terminate()
  controller:terminate()
end

-- --- Calibrator UI and helpers -------------------------------------------------

-- Expose minimal API for UI integration and console
local function setUseItemOffsets(enabled)
  USE_ITEM_OFFSETS = not not enabled
  saveOffsets()
end

-- Determine if current player is allowed to open the calibrator (GM/God)
local function isCalibratorAllowed()
  local p = g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  local isGm = (g_game.isGM and g_game.isGM()) or false
  local gmActions = (g_game.getGMActions and g_game.getGMActions()) or nil
  local gmActionsHasAny = false
  if type(gmActions) == 'table' then for _ in pairs(gmActions) do gmActionsHasAny = true; break end end
  local groupId = p and p.getGroup and p:getGroup() or nil
  local accountType = p and p.getAccountType and p:getAccountType() or nil
  print(string.format('[Calibrator] perms: isGM=%s, GMActions=%s, group=%s, accountType=%s',
    isGm and 'true' or 'false', gmActionsHasAny and 'true' or 'false', tostring(groupId), tostring(accountType)))
  if isGm or gmActionsHasAny then return true end
  if type(groupId) == 'number' and groupId >= 6 then return true end -- player type (god) = 6
  if type(accountType) == 'number' and accountType >= 5 then return true end -- account type (god) = 5
  return false
end

local function getCurrentDirKey()
  local p = g_game.getLocalPlayer()
  local dir = p and (p.getDirection and p:getDirection() or South) or South
  return DIR_TO_KEY[dir] or 'S'
end

function paperdoll_get_current_dir_key()
  return getCurrentDirKey()
end

function paperdoll_get_active_item_id(slotName)
  local slot = resolveSlotId and resolveSlotId(slotName) or nil
  if not slot then return 0 end
  local p = g_game.getLocalPlayer(); if not p then return 0 end
  local it = p:getInventoryItem(slot); if not it then return 0 end
  return it:getId()
end

function paperdoll_save_offsets()
  saveOffsets()
end

function paperdoll_nudge_item(slotName, dirKey, dx, dy)
  local slot = resolveSlotId and resolveSlotId(slotName) or nil
  if not slot then return nil end
  local p = g_game.getLocalPlayer(); if not p then return nil end
  local it = p:getInventoryItem(slot); if not it then return nil end
  local key = tostring(it:getId())
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].items = OFFSETS[slotName].items or {}
  local dk = (function(k) if type(k) ~= 'string' or #k == 0 then return 'S' end local c=k:sub(1,1):upper(); if c=='N' or c=='E' or c=='S' or c=='W' then return c end return 'S' end)(dirKey)
  local m = OFFSETS[slotName].items
  local v = (m[key] and m[key][dk]) or {0,0,true}
  v[1] = (v[1] or 0) - (dx or 0)
  v[2] = (v[2] or 0) - (dy or 0)
  m[key] = m[key] or {}; m[key][dk] = v
  saveOffsets(); updateManagerConfigFor(slot, it:getId()); applyOffsetsToActive(slot)
  return v
end

function paperdoll_clear_item_offsets(slotName)
  loadOffsets()
  local slot = resolveSlotId and resolveSlotId(slotName) or nil
  if not slot then return end
  local p = g_game.getLocalPlayer(); if not p then return end
  local it = p:getInventoryItem(slot); if not it then return end
  local key = tostring(it:getId())
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].items = OFFSETS[slotName].items or {}
  OFFSETS[slotName].items[key] = nil
  saveOffsets(); updateManagerConfigFor(slot, it:getId()); applyOffsetsToActive(slot)
end

-- Defaults for Reset Slot
local function makeDefaultForSlot(slotName)
  if slotName == 'head' then
    return { N={31,37,true}, E={32,33,true}, S={33,32,true}, W={35,30,true} }
  elseif slotName == 'body' then
    return { N={32,34,true}, E={33,33,true}, S={33,34,true}, W={34,31,true} }
  end
  return { N={0,0,true}, E={0,0,true}, S={0,0,true}, W={0,0,true} }
end

-- Window loader
local function openPaperdollCalibratorInternal()
  if not g_ui or not g_ui.getRootWidget then
    return print('Calibrator UI not available, using console helpers.')
  end
  -- Restrict calibrator to GM/God accounts only
  local allowed = isCalibratorAllowed()
  print(string.format('[Calibrator] god status check: %s', allowed and 'true' or 'false'))
  if not allowed then
    print('[Calibrator] access denied: Calibrator is restricted to GM accounts.')
    return
  end
  local root = g_ui.getRootWidget()
  if modules.game_paperdoll_overlay._calibWnd and modules.game_paperdoll_overlay._calibWnd:isVisible() then
    modules.game_paperdoll_overlay._calibWnd:raise(); modules.game_paperdoll_overlay._calibWnd:focus(); return
  end
  local wnd = (g_ui.displayUI and g_ui.displayUI('paperdoll_calibrator')) or nil
  if not wnd then
    wnd = g_ui.loadUI('/game_paperdoll_overlay/paperdoll_calibrator', root) or g_ui.loadUI('paperdoll_calibrator', root)
  end
  if not wnd then
    print('[Calibrator] failed to load UI window (paperdoll_calibrator).')
  end
  if wnd and wnd.show then
    wnd:show(); wnd:raise(); wnd:focus()
    pcall(function()
      local setup = (modules and modules.game_paperdoll_overlay and modules.game_paperdoll_overlay.onCalibratorSetup) or onCalibratorSetup
      if setup then setup(wnd) end
    end)
  end
  modules.game_paperdoll_overlay._calibWnd = wnd
end

modules.game_paperdoll_overlay = modules.game_paperdoll_overlay or {}
modules.game_paperdoll_overlay.openPaperdollCalibrator = openPaperdollCalibratorInternal

function openPaperdollCalibrator()
  return openPaperdollCalibratorInternal()
end

-- UI controller
function controller:onCalibratorSetup(w)
  w._slotIndex = 4 -- default 'body'
  local ALL_SLOTS = { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
  w._allSlots = ALL_SLOTS
  local slotValue = w:recursiveGetChildById('slotValue') or w:getChildById('slotValue')
  if slotValue then slotValue:setText(ALL_SLOTS[w._slotIndex]) end
  local perItem = w.recursiveGetChildById and w:recursiveGetChildById('perItemCheck') or w:getChildById('perItemCheck')
  if perItem then perItem:setChecked(USE_ITEM_OFFSETS) end
  -- show current item id if available
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then
    idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(ALL_SLOTS[w._slotIndex] or 'body')))
  end
  -- enable/disable arrows depending on PNG availability for current slot
  local function updateArrowsEnabled()
    local slot = ALL_SLOTS[w._slotIndex or 4]
    local slotId = resolveSlotId(slot)
    local has = false
    local p = g_game.getLocalPlayer()
    if p and slotId then
      local it = p:getInventoryItem(slotId)
      if it then
        local paths = findDirectionalPNGs(slotId, it:getId())
        has = next(paths) ~= nil
      end
    end
    for _, bid in ipairs({ 'btnLeft','btnRight','btnUp','btnDown' }) do
      local b = w:recursiveGetChildById(bid) or w:getChildById(bid)
      if b and b.setEnabled then b:setEnabled(has) end
    end
  end
  updateArrowsEnabled(); w._updateArrowsEnabled = updateArrowsEnabled
  -- set and auto-update current facing direction label
  local dirLabel = w:recursiveGetChildById('dirVal') or w:getChildById('dirVal')
  if dirLabel then dirLabel:setText(paperdoll_get_current_dir_key and paperdoll_get_current_dir_key() or 'S') end
  controller:cycleEvent(function()
    if not modules.game_paperdoll_overlay._calibWnd or modules.game_paperdoll_overlay._calibWnd:isDestroyed() then return end
    if not modules.game_paperdoll_overlay._calibWnd:isVisible() then return end
    local lbl = w:recursiveGetChildById('dirVal') or w:getChildById('dirVal')
    if lbl then lbl:setText(paperdoll_get_current_dir_key and paperdoll_get_current_dir_key() or 'S') end
  end, 200, 'paperdoll_calib_dir')
end

local function getSelectedForUI(w)
  local ALL_SLOTS = w._allSlots or { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
  local slot = ALL_SLOTS[w._slotIndex or 4]
  local stepWidget = (w.recursiveGetChildById and w:recursiveGetChildById('stepSpin')) or w:getChildById('stepSpin')
  local step = (stepWidget and (stepWidget.getValue and stepWidget:getValue() or tonumber(stepWidget:getText()))) or 1
  local dirKey = paperdoll_get_current_dir_key and paperdoll_get_current_dir_key() or 'S'
  return slot, dirKey, step
end

function controller:onAdjustClick(axis, sign)
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  local slot, dir, step = getSelectedForUI(w)
  local dx, dy = 0, 0
  if axis == 'x' then dx = sign * step else dy = sign * step end
  local v
  if USE_ITEM_OFFSETS and paperdoll_get_active_item_id and paperdoll_get_active_item_id(slot) ~= 0 then
    v = paperdoll_nudge_item(slot, dir, dx, dy)
  else
    -- call internal nudge (slot-level)
    v = (function()
      loadOffsets();
      local dk = (function(k) if type(k) ~= 'string' or #k == 0 then return 'S' end local c=k:sub(1,1):upper(); if c=='N' or c=='E' or c=='S' or c=='W' then return c end return 'S' end)(dir)
      OFFSETS[slot] = OFFSETS[slot] or {}
      OFFSETS[slot].default = OFFSETS[slot].default or {}
      local vv = OFFSETS[slot].default[dk] or {0,0,true}
      vv[1] = (vv[1] or 0) - (dx or 0)
      vv[2] = (vv[2] or 0) - (dy or 0)
      OFFSETS[slot].default[dk] = vv
      saveOffsets()
      local p = g_game.getLocalPlayer(); if not p then return vv end
      local slotId = resolveSlotId(slot); if not slotId then return vv end
      local it = p:getInventoryItem(slotId)
      if it then updateManagerConfigFor(slotId, it:getId()); applyOffsetsToActive(slotId) end
      return vv
    end)()
  end
  local vx = (type(v) == 'table' and v[1]) or 0
  local vy = (type(v) == 'table' and v[2]) or 0
  local offLbl = w:recursiveGetChildById('offsetValue') or w:getChildById('offsetValue')
  if offLbl and offLbl.setText then offLbl:setText(string.format('(%d,%d,true)', vx, vy)) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(slot))) end
end

function controller:onPerItemToggle(widget, checked)
  setUseItemOffsets(checked)
end

function controller:onCloseCalibrator()
  if modules.game_paperdoll_overlay._calibWnd then modules.game_paperdoll_overlay._calibWnd:destroy(); modules.game_paperdoll_overlay._calibWnd = nil end
end

function controller:onUseCurrentDir()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  local dirLabel = w:recursiveGetChildById('dirVal') or w:getChildById('dirVal')
  if dirLabel then dirLabel:setText(paperdoll_get_current_dir_key and paperdoll_get_current_dir_key() or 'S') end
end

function controller:onSaveOffsets()
  saveOffsets()
end

function controller:onClearItem()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  local slot, _, _ = getSelectedForUI(w)
  if paperdoll_clear_item_offsets then paperdoll_clear_item_offsets(slot) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(slot))) end
end

function controller:onResetSlot()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  local slot, _, _ = getSelectedForUI(w)
  loadOffsets()
  OFFSETS[slot] = OFFSETS[slot] or {}
  OFFSETS[slot].default = makeDefaultForSlot(slot)
  saveOffsets()
  local p = g_game.getLocalPlayer(); if not p then return end
  local slotId = resolveSlotId(slot); if not slotId then return end
  local it = p:getInventoryItem(slotId)
  if it then updateManagerConfigFor(slotId, it:getId()); applyOffsetsToActive(slotId) end
end

function controller:onExport()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  local slot, _, _ = getSelectedForUI(w)
  loadOffsets()
  local data = OFFSETS[slot] or {}
  local function fmt(k)
    local v = (data.default and data.default[k]) or {0,0,true}
    return string.format('%s=(%d,%d,%s)', k, v[1] or 0, v[2] or 0, (v[3] and 'true' or 'false'))
  end
  print(string.format('[Calibrator] %s defaults: %s %s %s %s', slot:gsub('^%l', string.upper), fmt('N'), fmt('E'), fmt('S'), fmt('W')))
end

function controller:onSlotPrev()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  w._slotIndex = math.max(1, (w._slotIndex or 4) - 1)
  local ALL_SLOTS = w._allSlots or { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
  local slotValue = w:recursiveGetChildById('slotValue') or w:getChildById('slotValue')
  if slotValue then slotValue:setText(ALL_SLOTS[w._slotIndex]) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(ALL_SLOTS[w._slotIndex]))) end
  if w._updateArrowsEnabled then w._updateArrowsEnabled() end
end

function controller:onSlotNext()
  local w = modules.game_paperdoll_overlay._calibWnd; if not w then return end
  w._slotIndex = math.min(#(w._allSlots or { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }), (w._slotIndex or 4) + 1)
  local ALL_SLOTS = w._allSlots or { 'head','neck','back','body','right','left','legs','feet','finger','ammo','purse' }
  local slotValue = w:recursiveGetChildById('slotValue') or w:getChildById('slotValue')
  if slotValue then slotValue:setText(ALL_SLOTS[w._slotIndex]) end
  local idLbl = w:recursiveGetChildById('itemIdLabel') or w:getChildById('itemIdLabel')
  if idLbl and paperdoll_get_active_item_id then idLbl:setText(string.format('Item: %d', paperdoll_get_active_item_id(ALL_SLOTS[w._slotIndex]))) end
  if w._updateArrowsEnabled then w._updateArrowsEnabled() end
end

-- Export UI callbacks under module namespace for OTUI
modules.game_paperdoll_overlay.onCalibratorSetup = function(w) controller:onCalibratorSetup(w) end
modules.game_paperdoll_overlay.onAdjustClick = function(axis, sign) controller:onAdjustClick(axis, sign) end
modules.game_paperdoll_overlay.onPerItemToggle = function(widget, checked) controller:onPerItemToggle(widget, checked) end
modules.game_paperdoll_overlay.onCloseCalibrator = function() controller:onCloseCalibrator() end
modules.game_paperdoll_overlay.onUseCurrentDir = function() controller:onUseCurrentDir() end
modules.game_paperdoll_overlay.onSaveOffsets = function() controller:onSaveOffsets() end
modules.game_paperdoll_overlay.onClearItem = function() controller:onClearItem() end
modules.game_paperdoll_overlay.onResetSlot = function() controller:onResetSlot() end
modules.game_paperdoll_overlay.onExport = function() controller:onExport() end
modules.game_paperdoll_overlay.onSlotPrev = function() controller:onSlotPrev() end
modules.game_paperdoll_overlay.onSlotNext = function() controller:onSlotNext() end
