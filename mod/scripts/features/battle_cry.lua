local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"

local function OnBattleCryRequest(player)
    if player == nil or not player:IsValid() then
        return
    end

    local rider = player.components.rider
    if rider == nil or not rider:IsRiding() then
        return
    end

    local beefalo = rider:GetMount()
    if beefalo == nil or not beefalo:IsValid() or beefalo.prefab ~= "beefalo" then
        return
    end

    if beefalo.sg == nil
        or beefalo.sg:HasStateTag("busy")
        or beefalo.sg:HasStateTag("attack") then
        return
    end

    beefalo.sg:GoToState("bellow")
end

AddModRPCHandler(RPC_NAMESPACE, RPC_COMMAND, OnBattleCryRequest)

local function OnBattleCryKeyDown()
    local player = GLOBAL.ThePlayer
    if player == nil or player.HUD == nil then
        return
    end

    if GLOBAL.TheFrontEnd:GetActiveScreen() ~= player.HUD
        or player.HUD:IsChatInputScreenOpen()
        or player.HUD:IsConsoleScreenOpen() then
        return
    end

    GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][RPC_COMMAND])
end

if not GLOBAL.TheNet:IsDedicated() then
    local key = GetModConfigData("battle_cry_key", true)
    if key == nil then
        key = GLOBAL.KEY_H
    end

    if key >= 0 then
        GLOBAL.TheInput:AddKeyDownHandler(key, OnBattleCryKeyDown)
    end
end
