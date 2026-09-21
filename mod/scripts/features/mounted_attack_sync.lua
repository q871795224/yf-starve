local ATTACK_STATE = "yf_mounted_weapon_attack"
local ATTACK_HIT_FRAME = 10

local function IsMasterSim()
    return GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim
end

local function GetMeleeWeapon(inst)
    local inventory = inst.components.inventory
    local weapon = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
    if weapon == nil or weapon.components.weapon == nil then
        return nil
    end

    if weapon.components.weapon.projectile ~= nil then
        return nil
    end

    return weapon
end

local function PlayMountedAttackAnimation(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end

    -- Existing mounted-player animations; no custom animation assets are needed.
    inst.AnimState:PlayAnimation("player_atk_pre")
    inst.AnimState:PushAnimation("player_atk", false)
end

local function FinishMountedAttack(inst)
    if inst.AnimState:AnimDone() then
        inst.sg:GoToState("idle")
    end
end

local function DoMountedWeaponAttack(inst)
    local statemem = inst.sg.statemem
    local target = statemem.target
    if target == nil or not target:IsValid() then
        return
    end

    local rider = inst.components.rider
    if rider == nil or not rider:IsRiding() or rider:GetMount() ~= statemem.mount then
        return
    end

    if GetMeleeWeapon(inst) ~= statemem.weapon then
        return
    end

    local combat = inst.components.combat
    if combat ~= nil then
        combat:DoAttack(target)
    end
end

AddStategraphPostInit("wilson", function(sg)
    sg.states[ATTACK_STATE] = GLOBAL.State{
        name = ATTACK_STATE,
        tags = { "attack", "busy" },

        onenter = function(inst, data)
            inst.sg.statemem.target = data ~= nil and data.target or nil
            inst.sg.statemem.mount = data ~= nil and data.mount or nil
            inst.sg.statemem.weapon = data ~= nil and data.weapon or nil

            PlayMountedAttackAnimation(inst)

            if inst.components.combat ~= nil then
                inst.components.combat:StartAttack()
            end
        end,

        timeline = {
            GLOBAL.TimeEvent(ATTACK_HIT_FRAME * GLOBAL.FRAMES, DoMountedWeaponAttack),
        },

        events = {
            GLOBAL.EventHandler("animover", FinishMountedAttack),
        },
    }
end)

AddStategraphPostInit("wilson_client", function(sg)
    sg.states[ATTACK_STATE] = GLOBAL.State{
        name = ATTACK_STATE,
        tags = { "attack", "busy" },
        server_states = { ATTACK_STATE },

        onenter = PlayMountedAttackAnimation,

        events = {
            GLOBAL.EventHandler("animover", FinishMountedAttack),
        },
    }
end)

local function OnBeefaloAttackOther(beefalo, data)
    local target = data ~= nil and data.target or nil
    if target == nil or not target:IsValid() then
        return
    end

    local rideable = beefalo.components.rideable
    local rider = rideable ~= nil and rideable.rider or nil
    if rider == nil or not rider:IsValid() then
        return
    end

    local combat = rider.components.combat
    local mounted = rider.components.rider
    local weapon = GetMeleeWeapon(rider)
    if combat == nil or mounted == nil or weapon == nil or rider.sg == nil then
        return
    end

    if not mounted:IsRiding() or mounted:GetMount() ~= beefalo or rider.sg:HasStateTag("busy") then
        return
    end

    -- The beefalo's hit has already resolved. The rider's separate weapon hit
    -- is applied at the mounted swing's timeline frame.
    rider.sg:GoToState(ATTACK_STATE, {
        target = target,
        mount = beefalo,
        weapon = weapon,
    })
end

local function OnBeefaloPostInit(inst)
    if not IsMasterSim() then
        return
    end

    inst:ListenForEvent("onattackother", OnBeefaloAttackOther)
end

AddPrefabPostInit("beefalo", OnBeefaloPostInit)
