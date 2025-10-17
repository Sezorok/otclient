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

-- adicionado por cursors: desabilitar o slot 'back' temporariamente (presente, porém inoperante)
local DISABLED_PAPERDOLL_SLOTS = {
  [InventorySlotBack] = true,
}

-- adicionado por cursors: helper para verificar se um slot está desabilitado
local function slotDisabled(slot)
  return DISABLED_PAPERDOLL_SLOTS and DISABLED_PAPERDOLL_SLOTS[slot] or false
end

local DIR_INDEX = { [North] = 0, [East] = 1, [South] = 2, [West] = 3 }
local INDEX_TO_DIR = { North, East, South, West }

local function applyDefaultOffsets(eff)
  eff:setDirOffset(North, 0, -6, true)
  eff:setDirOffset(East,  6, -4, true)
  eff:setDirOffset(South, 0,  8, true)
  eff:setDirOffset(West, -6, -4, true)
end

local state = { current = {}, activeEffect = {}, frameIdx = {} }
-- adicionado por cursors: timestamp do último passo, para animar apenas enquanto há movimento
local lastWalkAtMs = 0
-- must be defined before functions to be captured as upvalue
local invisByCreature = {}

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
  if itemId and conf.items and conf.items[tostring(itemId)] then
    return conf.items[tostring(itemId)], true
  end
  return conf.default, false
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

-- adicionado por cursors: suportar multi-frame por direção no id do efeito
-- Mantém compatibilidade: frameIdx padrão = 0 preserva IDs antigos
local function makeEffectId(slot, itemId, dirIdx, frameIdx)
  local frame = frameIdx or 0
  return SLOT_BASE[slot] + (itemId % 10000) + (dirIdx or 0) + (frame * 1000)
end

local BASE_DIRS = { "/images/paperdll/", "/images/paperdoll/" } -- support both spellings

-- adicionado por cursors: localizar PNGs por direção com suporte a multi-frames
local function findDirectionalPNGs(slot, itemId)
  local dirName = SLOT_DIR[slot]
  if not dirName then return {} end
  local map = {}
  for _, baseDir in ipairs(BASE_DIRS) do
    local any = false
    -- Primeiro tenta padrão multi-frame: <id>_<dir>_<frame>.png
    local foundMulti = false
    for i = 0, 3 do
      local frames = {}
      local f = 0
      -- limite razoável de frames para evitar loop infinito
      while f <= 15 do
        local path = string.format("%s%s/%d_%d_%d.png", baseDir, dirName, itemId, i, f)
        if g_resources.fileExists(path) then
          table.insert(frames, path)
          any = true; foundMulti = true
          f = f + 1
        else
          break
        end
      end
      if #frames > 0 then map[i] = frames end
    end
    if foundMulti then return map end
    -- Fallback para 1 frame por direção: <id>_<dir>.png
    for i = 0, 3 do
      local path = string.format("%s%s/%d_%d.png", baseDir, dirName, itemId, i)
      if g_resources.fileExists(path) then map[i] = { path }; any = true end
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

-- adicionado por cursors: registrar efeitos para cada frame existente por direção
local function ensureEffects(slot, itemId, dirPaths)
  for i = 0, 3 do
    local frames = dirPaths[i]
    if type(frames) == 'string' then frames = { frames } end
    if type(frames) == 'table' then
      for fIdx, path in ipairs(frames) do
        local effId = makeEffectId(slot, itemId, i, (fIdx - 1))
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
end

-- adicionado por cursors: trocar efeito considerando múltiplos frames
local function switchDirEffect(player, slot, itemId, dirIdx, dirPaths, forceRestart, effectDir, frameIdx)
  local frames = dirPaths[dirIdx]
  if type(frames) == 'string' then frames = { frames } end
  local wantedDirIdx = dirIdx
  if not frames or #frames == 0 then
    -- remap diagonals or missing dirs to nearest horizontal first, then south as fallback
    local mappedIdx = resolveDirIdxForEffect(INDEX_TO_DIR[dirIdx] or dirIdx)
    if dirPaths[mappedIdx] then
      wantedDirIdx = mappedIdx; frames = dirPaths[mappedIdx]
    elseif dirPaths[2] then
      wantedDirIdx = 2; frames = dirPaths[2]
    else
      for i = 0, 3 do if dirPaths[i] then wantedDirIdx = i; frames = dirPaths[i]; break end end
    end
  end
  if type(frames) == 'string' then frames = { frames } end
  local numFrames = (type(frames) == 'table') and #frames or 0
  local fIdx = frameIdx or 0
  if numFrames > 0 then fIdx = fIdx % numFrames end
  local wantedEffId = makeEffectId(slot, itemId, wantedDirIdx, fIdx)
  local active = state.activeEffect[slot]
  if forceRestart or (active and active ~= wantedEffId) or (player.getAttachedEffectById and not player:getAttachedEffectById(wantedEffId)) then
    local eff = g_attachedEffects.getById(wantedEffId)
    if eff then
      -- Apply latest offsets at attach time so runtime changes take effect
      applyOffsetsForAllDirs(eff, slot, itemId)
      -- Ensure effect respects current facing direction for dir-specific offsets
      local dirConst = effectDir or (INDEX_TO_DIR[wantedDirIdx] or South)
      if eff.setDirection then eff:setDirection(dirConst) end
      -- attach new first to avoid visual gap, then detach old if needed
      player:attachEffect(eff)
      if active and active ~= wantedEffId and player.detachEffectById then
        player:detachEffectById(active)
      end
      state.activeEffect[slot] = wantedEffId
      -- adicionado por cursors: memorizar frame atual para congelar quando parado
      state.frameIdx[slot] = fIdx
    end
  else
    state.activeEffect[slot] = wantedEffId
    state.frameIdx[slot] = fIdx
  end
end

local function updateSlotOverlay(player, slot, item)
  if not slot then return end
  -- adicionado por cursors: ignorar processamento de overlays para slots desabilitados (ex.: back)
  if slotDisabled(slot) then return end
  -- Do not (re)attach overlays while invisible
  local cid = player.getId and player:getId() or nil
  local isInv = (player.isInvisible and player:isInvisible()) or (cid and invisByCreature[cid])
  if isInv then
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
  -- adicionado por cursors: iniciar no frame 0
  switchDirEffect(player, slot, itemId, dirIdx, dirPaths, false, nil, 0)
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
                    -- adicionado por cursors: não registrar efeitos para slots desabilitados (ex.: back)
                    if slot and not slotDisabled(slot) then
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
      -- Prefer engine-side invisibility flag for robustness; fallback to outfit heuristic
      local inv = (creature.isInvisible and creature:isInvisible()) or isInvisible(outfit)
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
    -- Skip initial attach while invisible
    if not (p.isInvisible and p:isInvisible()) then
      for s = first, last do
        -- adicionado por cursors: pular slots desabilitados (ex.: back)
        if not slotDisabled(s) then
          updateSlotOverlay(p, s, p:getInventoryItem(s))
        end
      end
    end
    -- React to manual walk start to keep overlays aligned while walking
    self:registerEvents(g_game, {
      onWalk = function(_direction)
        -- adicionado por cursors: registrar último passo
        lastWalkAtMs = g_clock.millis()
        local cid = p.getId and p:getId() or nil
        if (p.isInvisible and p:isInvisible()) or (cid and invisByCreature[cid]) then return end
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
        -- adicionado por cursors: registrar último passo/auto-walk
        lastWalkAtMs = g_clock.millis()
        local cid = p.getId and p:getId() or nil
        if (p.isInvisible and p:isInvisible()) or (cid and invisByCreature[cid]) then return end
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
      if (p.isInvisible and p:isInvisible()) or (cid and invisByCreature[cid]) then
        -- While invisible, skip direction switches and inventory re-attach attempts
        return
      end
      -- Continuously apply latest offsets to all active overlays to reflect live tweaks
      for s, _ in pairs(state.current) do applyOffsetsToActive(s) end
      local dir = p.getDirection and p:getDirection() or South
      local dirIdx = resolveDirIdxForEffect(dir)
      -- adicionado por cursors: animar somente quando andando (ou nos ~350ms após um passo)
      local isWalking = false
      do
        local lp = g_game.getLocalPlayer()
        if lp and lp.isWalking and lp:isWalking() then
          isWalking = true
        else
          local now = g_clock.millis()
          isWalking = (now - (lastWalkAtMs or 0)) < 350
        end
      end
      local advanceFrame = 0
      if isWalking then
        -- OBS: usar divisão comum para compatibilidade com LuaJIT (sem operador // do Lua 5.3)
        advanceFrame = (math.floor(g_clock.millis() / 200) % 3)
      end
      if dirIdx ~= lastDirIdx then advanceFrame = 0 end
      for s, itemId in pairs(state.current) do
        if not slotDisabled(s) then
          local dirPaths = findDirectionalPNGs(s, itemId)
          if next(dirPaths) ~= nil then
            -- se parado, reutiliza o último frame escolhido para o slot
            local useFrame = isWalking and advanceFrame or state.frameIdx[s] or 0
            switchDirEffect(p, s, itemId, dirIdx, dirPaths, false, nil, useFrame)
          end
        end
      end
      lastDirIdx = dirIdx
      -- Inventory sync: ensure overlays attach/detach even if onInventoryChange isn't fired
      for s = first, last do
        if not slotDisabled(s) then
          local it = p:getInventoryItem(s)
          local curr = state.current[s]
          local currId = curr
          local itId = it and it:getId() or nil
          if itId ~= currId then
            updateSlotOverlay(p, s, it)
          end
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
