local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"

local function OnMountedBellowProbe()
    print("[yf-starve] animation_probe F10: rider wilsonbeefalo bellow")

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

    GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][RPC_COMMAND])
end

if not GLOBAL.TheNet:IsDedicated() then
    GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_F10, OnMountedBellowProbe)
    print("[yf-starve] registered animation_probe: F10 plays mounted-player bellow")
end
