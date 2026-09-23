local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "mounted_lancejab"

local LANCE_STATE = "yf_mounted_lancejab"
local LANCE_PRE_ANIMATION = "yf_mounted_lancejab_pre"
local LANCE_ANIMATION = "yf_mounted_lancejab"
local LANCE_DURATION = 23 * GLOBAL.FRAMES

local function IsRidingBeefalo(player)
    local rider = player ~= nil and player.components.rider or nil
    if rider == nil or not rider:IsRiding() then
        return nil
    end

    local beefalo = rider:GetMount()
    if beefalo == nil or not beefalo:IsValid() or beefalo.prefab ~= "beefalo" then
        return nil
    end

    return beefalo
end

local function StopRider(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end
end

local function PlayLanceAnimation(inst)
    StopRider(inst)
    -- The offline preview uses a merged build. In-game the rider keeps its
    -- normal mounted build, so map the separate lance build onto the custom
    -- animation symbol for the duration of this state.
    inst.AnimState:OverrideSymbol("swap_spear_lance", "swap_spear_lance", "swap_spear_lance")
    inst.AnimState:PlayAnimation(LANCE_PRE_ANIMATION, false)
    inst.AnimState:PushAnimation(LANCE_ANIMATION, false)
end

local function PlayBeefaloAttackAnimation(beefalo)
    if beefalo.components.locomotor ~= nil then
        beefalo.components.locomotor:StopMoving()
    end

    -- Keep the cow's vanilla upward head/torso motion in phase with the
    -- rider's custom lance motion. This is presentation only; the cow's
    -- stategraph is left untouched and no attack event is emitted here.
    beefalo.AnimState:PlayAnimation("atk_pre", false)
    beefalo.AnimState:PushAnimation("atk", false)
end

local function FinishLance(inst)
    -- `animover` is also emitted when the queued pre clip hands off to the
    -- attack clip. Only leave the state after the complete queue is done.
    if inst.sg ~= nil
        and inst.sg:HasStateTag("yf_mounted_lance")
        and inst.AnimState:AnimDone() then
        inst.AnimState:ClearOverrideSymbol("swap_spear_lance")
        inst.sg:GoToState("idle")
    end
end

AddStategraphPostInit("wilson", function(sg)
    sg.states[LANCE_STATE] = GLOBAL.State{
        name = LANCE_STATE,
        tags = { "busy", "attack", "yf_mounted_lance" },

        onenter = function(inst, data)
            inst.sg.statemem.mount = data ~= nil and data.mount or nil
            PlayLanceAnimation(inst)
            inst.sg:SetTimeout(LANCE_DURATION + 0.25)
            print("[yf-starve] mounted_lancejab state entered (23-frame visual pass)")
        end,

        onupdate = StopRider,

        ontimeout = FinishLance,

        events = {
            GLOBAL.EventHandler("animover", FinishLance),
        },
    }
end)

AddStategraphPostInit("wilson_client", function(sg)
    sg.states[LANCE_STATE] = GLOBAL.State{
        name = LANCE_STATE,
        tags = { "busy", "attack", "yf_mounted_lance" },
        server_states = { LANCE_STATE },

        onenter = function(inst)
            PlayLanceAnimation(inst)
            inst.sg:SetTimeout(LANCE_DURATION + 0.25)
        end,

        onupdate = StopRider,

        ontimeout = FinishLance,

        events = {
            GLOBAL.EventHandler("animover", FinishLance),
        },
    }
end)

local function OnLanceRequest(player)
    print("[yf-starve] RPC received: mounted_lancejab")

    if player == nil or not player:IsValid() then
        print("[yf-starve] mounted_lancejab rejected: invalid player")
        return
    end

    local beefalo = IsRidingBeefalo(player)
    if beefalo == nil then
        print("[yf-starve] mounted_lancejab rejected: player is not riding a beefalo")
        return
    end

    if player.sg == nil or player.sg:HasAnyStateTag("busy", "dead", "dismounting") then
        print("[yf-starve] mounted_lancejab rejected: rider is busy")
        return
    end

    if beefalo.sg == nil or beefalo.sg:HasAnyStateTag("busy", "attack", "dead") then
        print("[yf-starve] mounted_lancejab rejected: beefalo is busy")
        return
    end

    -- This first game pass is visual only. It deliberately does not call
    -- combat:DoAttack, so it cannot duplicate the vanilla beefalo hit while
    -- we tune the mounted lance timing in-game.
    print("[yf-starve] mounted_lancejab accepted: playing visual pass")
    PlayBeefaloAttackAnimation(beefalo)
    player.sg:GoToState(LANCE_STATE, { mount = beefalo })
end

AddModRPCHandler(RPC_NAMESPACE, RPC_COMMAND, OnLanceRequest)

local function OnLanceKeyDown()
    print("[yf-starve] keydown: mounted_lancejab")

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

    print("[yf-starve] sending RPC: mounted_lancejab")
    GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][RPC_COMMAND])
end

if not GLOBAL.TheNet:IsDedicated() then
    local key = GetModConfigData("lance_key", true)
    if key == nil then
        key = GLOBAL.KEY_B
    end

    if key >= 0 then
        GLOBAL.TheInput:AddKeyDownHandler(key, OnLanceKeyDown)
        print("[yf-starve] registered mounted_lancejab key handler:", key)
    end
end
