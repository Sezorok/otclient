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

local function makeEffectId(slot, itemId, dirIdx)
  return SLOT_BASE[slot] + (itemId % 10000) + (dirIdx or 0)
end

local function findDirectionalPNGs(slot, itemId)
  local dirName = SLOT_DIR[slot]
  if not dirName then return {} end
  local base = string.format("/images/paperdll/%s/%d_", dirName, itemId)
  local map = {}
  for i = 0, 3 do
    local path = base .. i .. ".png"
    if g_resources.fileExists(path) then map[i] = path end
  end
  return map
end

local function ensureEffects(slot, itemId, dirPaths)
  for i = 0, 3 do
    local path = dirPaths[i]
    if path then
      local effId = makeEffectId(slot, itemId, i)
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
        registeredMeta[effId] = { slot = slot, itemId = itemId, dirIdx = i }
        if not registeredViaManager then
          local eff = g_attachedEffects.getById(effId)
          if eff then applySlotOffsets(slot, eff, i) end
        end
      end
    end
  end
end

local function switchDirEffect(player, slot, itemId, dirIdx, dirPaths)
  local wantedEffId = makeEffectId(slot, itemId, dirIdx)
  if not dirPaths[dirIdx] then
    if dirPaths[2] then
      wantedEffId = makeEffectId(slot, itemId, 2)
    else
      for i = 0, 3 do if dirPaths[i] then wantedEffId = makeEffectId(slot, itemId, i); break end end
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
    for s = InventorySlotFirst, InventorySlotLast do
      if SLOT_DIR[s] then
        updateSlotOverlay(p, s, p:getInventoryItem(s))
      end
    end
    self:cycleEvent(function()
      if not g_game.isOnline() then return end
      -- Invisibility guard: detach overlays while invisible
      local invNow = isInvisible(p.getOutfit and p:getOutfit() or nil)
      if invNow then
        if not wasInvisible then
          detachAllOverlays(p)
          wasInvisible = true
        end
        return
      elseif wasInvisible then
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
