local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"
local BATTLE_CRY_STATE = "yf_mounted_battle_cry"
local BATTLE_CRY_ANIMATION = "bellow"

local function PlayMountedBattleCryAnimation(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end

    -- Riding switches the rider to the wilsonbeefalo bank, which includes this clip.
    inst.AnimState:PlayAnimation(BATTLE_CRY_ANIMATION)
end

local function FinishMountedBattleCry(inst)
    if inst.AnimState:AnimDone() then
        inst.sg:GoToState("idle")
    end
end

AddStategraphPostInit("wilson", function(sg)
    sg.states[BATTLE_CRY_STATE] = GLOBAL.State{
        name = BATTLE_CRY_STATE,
        tags = { "busy", "canrotate" },

        onenter = function(inst)
            PlayMountedBattleCryAnimation(inst)

            local rider = inst.components.rider
            local mount = rider ~= nil and rider:GetMount() or nil
            if mount ~= nil and mount.sounds ~= nil and mount.sounds.grunt ~= nil then
                mount.SoundEmitter:PlaySound(mount.sounds.grunt)
            end
        end,

        events = {
            GLOBAL.EventHandler("animover", FinishMountedBattleCry),
        },
    }
end)

AddStategraphPostInit("wilson_client", function(sg)
    sg.states[BATTLE_CRY_STATE] = GLOBAL.State{
        name = BATTLE_CRY_STATE,
        tags = { "busy", "canrotate" },
        server_states = { BATTLE_CRY_STATE },

        onenter = PlayMountedBattleCryAnimation,

        events = {
            GLOBAL.EventHandler("animover", FinishMountedBattleCry),
        },
    }
end)

local function OnBattleCryRequest(player)
    print("[yf-starve] RPC received: battle_cry")

    if player == nil or not player:IsValid() then
        print("[yf-starve] battle_cry rejected: invalid player")
        return
    end

    local rider = player.components.rider
    if rider == nil or not rider:IsRiding() then
        print("[yf-starve] battle_cry rejected: player is not riding")
        return
    end

    local beefalo = rider:GetMount()
    if beefalo == nil or not beefalo:IsValid() or beefalo.prefab ~= "beefalo" then
        print("[yf-starve] battle_cry rejected: mount is not a valid beefalo")
        return
    end

    if beefalo.sg == nil or player.sg == nil then
        print("[yf-starve] battle_cry rejected: missing stategraph")
        return
    end

    local state = player.sg.currentstate
    if state ~= nil and state.name == BATTLE_CRY_STATE then
        print("[yf-starve] battle_cry rejected: animation is already playing")
        return
    end

    if player.sg:HasStateTag("busy") then
        print("[yf-starve] battle_cry rejected: rider is busy")
        return
    end

    if beefalo.sg:HasStateTag("busy") or beefalo.sg:HasStateTag("attack") then
        print("[yf-starve] battle_cry rejected: beefalo is busy or attacking")
        return
    end

    player.sg:GoToState(BATTLE_CRY_STATE)
    print("[yf-starve] battle_cry accepted: rider animation active:",
        player.AnimState:IsCurrentAnimation(BATTLE_CRY_ANIMATION))
end

AddModRPCHandler(RPC_NAMESPACE, RPC_COMMAND, OnBattleCryRequest)

local function OnBattleCryKeyDown()
    print("[yf-starve] keydown: battle_cry")

    local player = GLOBAL.ThePlayer
    if player == nil or player.HUD == nil then
        return
    end

    local active_screen = GLOBAL.TheFrontEnd:GetActiveScreen()
    if (active_screen ~= player.HUD and (active_screen == nil or active_screen.name ~= "HUD"))
        or player.HUD:IsChatInputScreenOpen()
        or player.HUD:IsConsoleScreenOpen() then
        return
    end

    print("[yf-starve] sending RPC: battle_cry")
    GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][RPC_COMMAND])
end

if not GLOBAL.TheNet:IsDedicated() then
    local key = GetModConfigData("battle_cry_key", true)
    if key == nil then
        key = GLOBAL.KEY_H
    end

    if key >= 0 then
        GLOBAL.TheInput:AddKeyDownHandler(key, OnBattleCryKeyDown)
        print("[yf-starve] registered battle_cry key handler:", key)
    end
end
