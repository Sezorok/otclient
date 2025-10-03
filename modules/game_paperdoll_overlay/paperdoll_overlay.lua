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
local INDEX_TO_DIR = { [0] = North, [1] = East, [2] = South, [3] = West }

local DEFAULT_DIR_OFFSETS = {
  [North] = { 0, -6, true },
  [East]  = { 6, -4, true },
  [South] = { 0,  8, true },
  [West]  = { -6, -4, true },
}

-- Per-slot directional offsets. Defaults can be tuned at runtime via
-- helper console functions exposed below.
local SLOT_OFFSETS = {
  [InventorySlotHead] = {
    [North] = { 32, 35, true },
    [East]  = { 32, 35, true },
    [South] = { 33, 32, true },
    [West]  = { 35, 33, true },
  },
  [InventorySlotBody] = {
    [North] = { 32, 32, true },
    [East]  = { 33, 33, true },
    [South] = { 32, 32, true },
    [West]  = { 33, 33, true },
  },
}

local function getDirOffsetsForSlot(slot)
  return SLOT_OFFSETS[slot] or DEFAULT_DIR_OFFSETS
end

-- Track current and registered effects before using helpers
local state = { current = {}, activeEffect = {} }
local registeredIds = {}
local registeredMeta = {} -- effId -> { slot=..., itemId=..., dirIdx=... }

local function applySlotOffsets(slot, eff, dirIdx)
  if not eff then return end
  local dir = INDEX_TO_DIR[dirIdx or 2] or South
  local dirOffsets = getDirOffsetsForSlot(slot)
  local o = dirOffsets[dir] or DEFAULT_DIR_OFFSETS[South]
  eff:setOnTop(true)
  eff:setOffset(o[1] or 0, o[2] or 0)
end

-- moved above

local function makeEffectId(slot, itemId, dirIdx, frameIdx)
  if frameIdx ~= nil then
    -- Reserve space to include per-frame ids without colliding with single-frame ids
    return SLOT_BASE[slot] + ((itemId % 10000) * 20) + (dirIdx or 0) * 5 + frameIdx
  end
  return SLOT_BASE[slot] + (itemId % 10000) + (dirIdx or 0)
end

local function findDirectionalPNGs(slot, itemId)
  -- Returns a map of dirIdx -> array of frame paths.
  -- Supports both single-frame naming:  <id>_<dir>.png
  -- and multi-frame naming:            <id>_<dir>_<frame>.png (frame = 0..N)
  local dirName = SLOT_DIR[slot]
  if not dirName then return {} end
  local base = string.format("/images/paperdll/%s/%d_", dirName, itemId)
  local map = {}
  for i = 0, 3 do
    local frames = {}
    local single = base .. i .. ".png"
    if g_resources.fileExists(single) then table.insert(frames, single) end
    -- probe up to 10 frames per direction (0..9)
    for f = 0, 9 do
      local pth = base .. i .. "_" .. f .. ".png"
      if g_resources.fileExists(pth) then table.insert(frames, pth) end
    end
    if #frames > 0 then map[i] = frames end
  end
  return map
end

local function ensureEffects(slot, itemId, dirPaths)
  for i = 0, 3 do
    local paths = dirPaths[i]
    if type(paths) == 'table' then
      for fIdx, path in ipairs(paths) do
        local frame = fIdx - 1
        local effId = makeEffectId(slot, itemId, i, frame)
        local already = registeredIds[effId]
        if not already then
          if AttachedEffectManager and AttachedEffectManager.get and AttachedEffectManager.get(effId) then
            registeredIds[effId] = true
            already = true
          end
        end
        if not already then
          local registeredViaManager = false
          if AttachedEffectManager and AttachedEffectManager.register and ThingExternalTexture then
            local dir = INDEX_TO_DIR[i]
            local dirOff = getDirOffsetsForSlot(slot)
            local o = dirOff[dir] or DEFAULT_DIR_OFFSETS[South]
            local cfg = { onTop = true, offset = { o[1] or 0, o[2] or 0, true } }
            AttachedEffectManager.register(effId, "paperdll", path, ThingExternalTexture, cfg)
            registeredViaManager = true
          else
            g_attachedEffects.registerByImage(effId, "paperdll", path, true)
          end
          registeredIds[effId] = true
          registeredMeta[effId] = { slot = slot, itemId = itemId, dirIdx = i, frameIdx = frame }
          if not registeredViaManager then
            local eff = g_attachedEffects.getById(effId)
            if eff then applySlotOffsets(slot, eff, i) end
          end
        end
      end
      -- Backward-compat: if only a single frame is present, also register the non-framed ID
      if #paths == 1 then
        local singleId = makeEffectId(slot, itemId, i)
        if not registeredIds[singleId] then
          local registeredViaManager = false
          if AttachedEffectManager and AttachedEffectManager.register and ThingExternalTexture then
            local dir = INDEX_TO_DIR[i]
            local dirOff = getDirOffsetsForSlot(slot)
            local o = dirOff[dir] or DEFAULT_DIR_OFFSETS[South]
            local cfg = { onTop = true, offset = { o[1] or 0, o[2] or 0, true } }
            AttachedEffectManager.register(singleId, "paperdll", paths[1], ThingExternalTexture, cfg)
            registeredViaManager = true
          else
            g_attachedEffects.registerByImage(singleId, "paperdll", paths[1], true)
          end
          registeredIds[singleId] = true
          registeredMeta[singleId] = { slot = slot, itemId = itemId, dirIdx = i, frameIdx = 0 }
          if not registeredViaManager then
            local eff = g_attachedEffects.getById(singleId)
            if eff then applySlotOffsets(slot, eff, i) end
          end
        end
      end
    end
  end
end

local function switchDirEffect(player, slot, itemId, dirIdx, dirPaths)
  local frames = dirPaths[dirIdx]
  local frameIdx = state.animFrame and state.animFrame[slot] or 0
  local wantedEffId = nil
  if type(frames) ~= 'table' or #frames == 0 then
    wantedEffId = makeEffectId(slot, itemId, dirIdx)
  else
    local count = #frames
    frameIdx = frameIdx % count
    wantedEffId = makeEffectId(slot, itemId, dirIdx, frameIdx)
  end
  if not frames then
    if dirPaths[2] then
      frames = dirPaths[2]
      if type(frames) == 'table' and #frames > 0 then
        wantedEffId = makeEffectId(slot, itemId, 2, 0)
      else
        wantedEffId = makeEffectId(slot, itemId, 2)
      end
    else
      for i = 0, 3 do if dirPaths[i] then
        if type(dirPaths[i]) == 'table' and #dirPaths[i] > 0 then
          wantedEffId = makeEffectId(slot, itemId, i, 0)
        else
          wantedEffId = makeEffectId(slot, itemId, i)
        end
        break
      end end
    end
  end
  local active = state.activeEffect[slot]
  if active and active ~= wantedEffId then
    if player:getAttachedEffectById(active) then
      player:detachEffectById(active)
    end
    state.activeEffect[slot] = nil
  end
  if not player:getAttachedEffectById(wantedEffId) then
    local eff = g_attachedEffects.getById(wantedEffId)
    if not eff then
      -- Fallback for legacy single-frame id
      local fallbackId = makeEffectId(slot, itemId, dirIdx)
      if registeredIds[fallbackId] then
        eff = g_attachedEffects.getById(fallbackId)
        wantedEffId = fallbackId
      end
    end
    if eff then
      -- reapply latest tuned offsets for this slot before attaching
      applySlotOffsets(slot, eff, dirIdx)
      player:attachEffect(eff)
      state.activeEffect[slot] = wantedEffId
    end
  else
    state.activeEffect[slot] = wantedEffId
  end
end

local function updateSlotOverlay(player, slot, item)
  if not slot or not SLOT_DIR[slot] then
    return
  end
  -- Do not attach overlays while invisible; ensure slot is cleared
  if player and player.isInvisible and player:isInvisible() then
    if state.activeEffect[slot] then
      local effId = state.activeEffect[slot]
      if player:getAttachedEffectById(effId) then
        player:detachEffectById(effId)
      end
      state.activeEffect[slot] = nil
    end
    state.current[slot] = nil
    return
  end
  if not item then
    if state.activeEffect[slot] then
      local effId = state.activeEffect[slot]
      if player:getAttachedEffectById(effId) then
        player:detachEffectById(effId)
      end
      state.activeEffect[slot] = nil
    end
    state.current[slot] = nil
    return
  end

  local itemId = item:getId()
  state.current[slot] = itemId

  local dirPaths = findDirectionalPNGs(slot, itemId)
  if next(dirPaths) == nil then return end
  ensureEffects(slot, itemId, dirPaths)

  local dir = player.getDirection and player:getDirection() or South
  local dirIdx = DIR_INDEX[dir] or 2
  switchDirEffect(player, slot, itemId, dirIdx, dirPaths)
end

local controller = Controller:new()
local lastDirIdx = nil
local wasInvisible = false
local cycleName = "paperdoll_dir"
local invisByCreature = {}

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

function init()
  controller:init()
  -- expose console helpers in global scope for easy tuning
  _G.paperdoll_print_head_offsets = paperdoll_print_head_offsets
  _G.paperdoll_set_head_offsets   = paperdoll_set_head_offsets
  _G.paperdoll_nudge_head         = paperdoll_nudge_head
  _G.paperdoll_print_body_offsets = paperdoll_print_body_offsets
  _G.paperdoll_set_body_offsets   = paperdoll_set_body_offsets
  _G.paperdoll_nudge_body         = paperdoll_nudge_body
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
      local inv = lp.isInvisible and lp:isInvisible() or false
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
    for s = InventorySlotFirst, InventorySlotLast do
      if SLOT_DIR[s] then
        updateSlotOverlay(p, s, p:getInventoryItem(s))
      end
    end
    self:cycleEvent(function()
      if not g_game.isOnline() then return end
      -- Invisibility guard: detach overlays while invisible
      local invNow = p.isInvisible and p:isInvisible() or false
      if invNow then
        if next(state.activeEffect) ~= nil then
          detachAllOverlays(p)
        end
        wasInvisible = true
        return
      end
      if wasInvisible then
        -- became visible again: restore overlays from inventory
        for s = InventorySlotFirst, InventorySlotLast do
          if SLOT_DIR[s] then
            updateSlotOverlay(p, s, p:getInventoryItem(s))
          end
        end
        wasInvisible = false
      end

      local dir = p.getDirection and p:getDirection() or South
      local dirIdx = DIR_INDEX[dir] or 2
      local walking = p.isWalking and p:isWalking() or false
      -- advance frame only while walking; reset to frame 0 when idle
      state.animFrame = state.animFrame or {}
      for s, itemId in pairs(state.current) do
        local dp = findDirectionalPNGs(s, itemId)
        local frames = dp[dirIdx]
        local count = (type(frames) == 'table') and #frames or 0
        if count > 1 then
          if walking then
            local nextIdx = ((state.animFrame[s] or 0) + 1) % count
            state.animFrame[s] = nextIdx
            switchDirEffect(p, s, itemId, dirIdx, dp)
          else
            if (state.animFrame[s] or 0) ~= 0 then
              state.animFrame[s] = 0
              switchDirEffect(p, s, itemId, dirIdx, dp)
            end
          end
        else
          state.animFrame[s] = 0
        end
      end
      if dirIdx ~= lastDirIdx then
        -- ensure ordering so head overlays body
        local ordered = {
          InventorySlotBody,
          InventorySlotLeg,
          InventorySlotFeet,
          InventorySlotRight,
          InventorySlotLeft,
          InventorySlotNeck,
          InventorySlotBack,
          InventorySlotFinger,
          InventorySlotAmmo,
          InventorySlotPurse,
          InventorySlotHead,
        }
        for _, s in ipairs(ordered) do
          local itemId = state.current[s]
          if itemId then
            local dirPaths = findDirectionalPNGs(s, itemId)
            if next(dirPaths) ~= nil then
              switchDirEffect(p, s, itemId, dirIdx, dirPaths)
            end
          end
        end
        lastDirIdx = dirIdx
      end
      -- Inventory sync: ensure overlays attach/detach even if onInventoryChange isn't fired
      for s = InventorySlotFirst, InventorySlotLast do
        if SLOT_DIR[s] then
          local it = p:getInventoryItem(s)
          local currId = state.current[s]
          local itId = it and it:getId() or nil
          if itId ~= currId then
            updateSlotOverlay(p, s, it)
          end
        end
      end
    end, 200, cycleName)
  end
end

function controller:onGameEnd()
  -- Do not actively detach on unload/reload to avoid race with
  -- other modules clearing the global attached effect registry.
  state.activeEffect = {}
  state.current = {}
end

function terminate()
  -- cleanup exported helpers
  _G.paperdoll_print_head_offsets = nil
  _G.paperdoll_set_head_offsets   = nil
  _G.paperdoll_nudge_head         = nil
  _G.paperdoll_print_body_offsets = nil
  _G.paperdoll_set_body_offsets   = nil
  _G.paperdoll_nudge_body         = nil
  controller:terminate()
end

-- Console helpers for offset tuning (head slot)
function paperdoll_print_head_offsets()
  local o = getDirOffsetsForSlot(InventorySlotHead)
  local n, e, s, w = o[North], o[East], o[South], o[West]
  print(string.format(
    "Head offsets: N=(%d,%d) E=(%d,%d) S=(%d,%d) W=(%d,%d)",
    n[1], n[2], e[1], e[2], s[1], s[2], w[1], w[2]
  ))
end

local function apply_offsets_to_all_for_slot(slot)
  -- Safer: only reapply on currently attached effects for the local player
  local p = g_game.getLocalPlayer()
  if not p then return end
  -- Update all registered prototypes for this slot
  for effId, meta in pairs(registeredMeta) do
    if meta.slot == slot then
      local proto = g_attachedEffects.getById(effId)
      if proto then
        applySlotOffsets(slot, proto, meta.dirIdx)
      end
    end
  end
  -- Update current attached instance for immediate visual feedback
  local activeId = state.activeEffect[slot]
  if activeId then
    local inst = p:getAttachedEffectById(activeId)
    if inst then
      local dirIdx = DIR_INDEX[p.getDirection and p:getDirection() or South] or 2
      applySlotOffsets(slot, inst, dirIdx)
    end
  end
end

function paperdoll_set_head_offsets(nx, ny, ex, ey, sx, sy, wx, wy)
  SLOT_OFFSETS[InventorySlotHead] = {
    [North] = { tonumber(nx) or 0, tonumber(ny) or 0, true },
    [East]  = { tonumber(ex) or 0, tonumber(ey) or 0, true },
    [South] = { tonumber(sx) or 0, tonumber(sy) or 0, true },
    [West]  = { tonumber(wx) or 0, tonumber(wy) or 0, true },
  }
  apply_offsets_to_all_for_slot(InventorySlotHead)
  paperdoll_print_head_offsets()
end

function paperdoll_nudge_head(dir, dx, dy)
  local map = { n = North, e = East, s = South, w = West }
  local d = map[string.lower(dir or '')]
  if not d then print('use: paperdoll_nudge_head(n|e|s|w, dx, dy)') return end
  local o = getDirOffsetsForSlot(InventorySlotHead)
  local v = o[d] or {0,0,true}
  v[1] = v[1] + (tonumber(dx) or 0)
  v[2] = v[2] + (tonumber(dy) or 0)
  o[d] = v
  apply_offsets_to_all_for_slot(InventorySlotHead)
  paperdoll_print_head_offsets()
end

-- Console helpers for offset tuning (body slot)
function paperdoll_print_body_offsets()
  local o = getDirOffsetsForSlot(InventorySlotBody)
  local n, e, s, w = o[North], o[East], o[South], o[West]
  print(string.format(
    "Body offsets: N=(%d,%d) E=(%d,%d) S=(%d,%d) W=(%d,%d)",
    n[1], n[2], e[1], e[2], s[1], s[2], w[1], w[2]
  ))
end

function paperdoll_set_body_offsets(nx, ny, ex, ey, sx, sy, wx, wy)
  SLOT_OFFSETS[InventorySlotBody] = {
    [North] = { tonumber(nx) or 0, tonumber(ny) or 0, true },
    [East]  = { tonumber(ex) or 0, tonumber(ey) or 0, true },
    [South] = { tonumber(sx) or 0, tonumber(sy) or 0, true },
    [West]  = { tonumber(wx) or 0, tonumber(wy) or 0, true },
  }
  apply_offsets_to_all_for_slot(InventorySlotBody)
  paperdoll_print_body_offsets()
end

function paperdoll_nudge_body(dir, dx, dy)
  local map = { n = North, e = East, s = South, w = West }
  local d = map[string.lower(dir or '')]
  if not d then print('use: paperdoll_nudge_body(n|e|s|w, dx, dy)') return end
  local o = getDirOffsetsForSlot(InventorySlotBody)
  local v = o[d] or {0,0,true}
  v[1] = v[1] + (tonumber(dx) or 0)
  v[2] = v[2] + (tonumber(dy) or 0)
  o[d] = v
  apply_offsets_to_all_for_slot(InventorySlotBody)
  paperdoll_print_body_offsets()
end
