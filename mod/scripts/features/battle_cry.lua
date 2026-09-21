local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"

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

    if beefalo.sg == nil then
        print("[yf-starve] battle_cry rejected: beefalo has no stategraph")
        return
    end

    local state = beefalo.sg.currentstate
    if state ~= nil and state.name == "bellow" then
        print("[yf-starve] battle_cry rejected: bellow animation is already playing")
        return
    end

    if beefalo.sg:HasStateTag("busy") then
        print("[yf-starve] battle_cry rejected: beefalo is busy in state", state ~= nil and state.name or "unknown")
        return
    end

    if beefalo.sg:HasStateTag("attack") then
        print("[yf-starve] battle_cry rejected: beefalo is attacking")
        return
    end

    beefalo.sg:GoToState("bellow")
    print("[yf-starve] battle_cry accepted: entered vanilla bellow state")
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
