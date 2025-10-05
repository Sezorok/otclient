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

-- Runtime-configurable offsets (persisted under /settings/paperdoll_offsets.json)
local OFFSETS = nil
local OFFSETS_PATH = "/settings/paperdoll_offsets.json"
local DIR_ALIAS = { N = North, E = East, S = South, W = West }
local DIR_TO_KEY = { [North] = 'N', [East] = 'E', [South] = 'S', [West] = 'W' }

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
  if itemId and conf.items and conf.items[tostring(itemId)] then
    return conf.items[tostring(itemId)], true
  end
  return conf.default, false
end

local function applyOffsetsForAllDirs(eff, slot, itemId)
  local map = getOffsetsFor(slot, itemId)
  if not map then applyDefaultOffsets(eff); return end
  local function applyDir(dirKey)
    local v = map[dirKey]
    if v then eff:setDirOffset(DIR_ALIAS[dirKey], v[1] or 0, v[2] or 0, v[3] and true or false) end
  end
  applyDir('N'); applyDir('E'); applyDir('S'); applyDir('W')
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

local function buildEffectConfig(slot, itemId)
  local cfg = { onTop = true, dirOffset = {} }
  -- default gentle bounce while walking; controlled at runtime
  cfg.bounce = { 0, 6, 800 }
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

local function switchDirEffect(player, slot, itemId, dirIdx, dirPaths, forceRestart)
  local wantedEffId = makeEffectId(slot, itemId, dirIdx)
  if not dirPaths[dirIdx] then
    if dirPaths[2] then
      wantedEffId = makeEffectId(slot, itemId, 2)
    else
      for i = 0, 3 do if dirPaths[i] then wantedEffId = makeEffectId(slot, itemId, i); break end end
    end
  end
  local active = state.activeEffect[slot]
  if active and (active ~= wantedEffId or forceRestart) then
    -- safe detach if API available, otherwise ignore
    if player.detachEffectById then
      player:detachEffectById(active)
    end
    state.activeEffect[slot] = nil
  end
  if forceRestart or not player.getAttachedEffectById or not player:getAttachedEffectById(wantedEffId) then
    local eff = g_attachedEffects.getById(wantedEffId)
    if eff then
      -- Apply latest offsets at attach time so runtime changes take effect
      applyOffsetsForAllDirs(eff, slot, itemId)
      player:attachEffect(eff)
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
end

function setItemOffsets(slotName, itemId, map)
  loadOffsets()
  OFFSETS[slotName] = OFFSETS[slotName] or {}
  OFFSETS[slotName].items = OFFSETS[slotName].items or {}
  OFFSETS[slotName].items[tostring(itemId)] = map
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
  v[1] = (v[1] or 0) + (dx or 0)
  v[2] = (v[2] or 0) + (dy or 0)
  OFFSETS[slotName].default[dk] = v
  return v
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
    local dirIdx = DIR_INDEX[dir] or 2
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
    local dirIdx = DIR_INDEX[dir] or 2
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
      onWalk = function(direction)
        local cid = p.getId and p:getId() or nil
        if cid and invisByCreature[cid] then return end
        local dirIdx = DIR_INDEX[direction] or nil
        if not dirIdx then return end
        -- restart overlay per slot on step start to kick bounce
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths, true)
          end
        end
      end,
      onAutoWalk = function(player, dirs)
        local cid = p.getId and p:getId() or nil
        if cid and invisByCreature[cid] then return end
        local dir = p.getDirection and p:getDirection() or South
        local dirIdx = DIR_INDEX[dir] or 2
        -- sustain gentle bounce while auto-walking
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths)
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
      local dir = p.getDirection and p:getDirection() or South
      local dirIdx = DIR_INDEX[dir] or 2
      if dirIdx ~= lastDirIdx then
        for s, itemId in pairs(state.current) do
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            switchDirEffect(p, s, itemId, dirIdx, dirPaths)
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
