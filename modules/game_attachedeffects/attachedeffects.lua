local function onAttach(effect, owner)
    if not AttachedEffectManager then return end
    local category, thingId = AttachedEffectManager.getDataThing(owner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)
    if not config then return end
    if config.isThingConfig then
        AttachedEffectManager.executeThingConfig(effect, category, thingId)
    end
    if config.onAttach then
        config.onAttach(effect, owner, config.__onAttach)
    end
end

local function onDetach(effect, oldOwner)
    if not AttachedEffectManager then return end
    local category, thingId = AttachedEffectManager.getDataThing(oldOwner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)
    if not config then return end
    if config.onDetach then
        config.onDetach(effect, oldOwner, config.__onDetach)
    end
end

local function onOutfitChange(creature, outfit, oldOutfit)
    -- Guard manager existence and effect validity
    if not AttachedEffectManager or not AttachedEffectManager.executeThingConfig then return end
    local ok, list = pcall(function() return creature:getAttachedEffects() end)
    if not ok or type(list) ~= 'table' then return end
    for _i, effect in pairs(list) do
        if effect and effect.getId then
            local cfg = AttachedEffectManager.getConfig(effect:getId(), ThingCategoryCreature, outfit.type)
            if cfg then
                AttachedEffectManager.executeThingConfig(effect, ThingCategoryCreature, outfit.type)
            end
        end
    end
end

controller = Controller:new()

function controller:onGameStart()
    controller:registerEvents(LocalPlayer, {
        onOutfitChange = onOutfitChange
    })

    controller:registerEvents(Creature, {
        onOutfitChange = onOutfitChange
    })

    controller:registerEvents(AttachedEffect, {
        onAttach = onAttach,
        onDetach = onDetach
    })

    -- uncomment this line to apply an effect on the local player, just for testing purposes.
    --[[g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(1))
    g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(2))
    g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(3))
    g_game.getLocalPlayer():getTile():attachEffect(g_attachedEffects.getById(1))
    g_game.getLocalPlayer():attachParticleEffect("creature-effect")]]
end

function controller:onGameEnd()
    -- g_game.getLocalPlayer():clearAttachedEffects()
end

function controller:onTerminate()
    g_attachedEffects.clear()
end

function getCategory(id)
    return AttachedEffectManager.get(id).thingCategory
end

function getTexture(id)
    if AttachedEffectManager.get(id).thingCategory == 5 then
        return AttachedEffectManager.get(id).thingId
    end
end

function getName(id)
    if type(id) == "number" then
        return AttachedEffectManager.get(id).name
    else
        return "None"
    end
end

function thingId(id)
    if type(id) == "number" then
        return AttachedEffectManager.get(id).thingId
    else
        return "None"
    end
end
