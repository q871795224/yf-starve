local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "mounted_tilling"
local SPEED_MULTIPLIER_KEY = "yf_mounted_tilling"
local TILL_SPEED_MULTIPLIER = 0.35
local TILL_HUNGER_COST = 4
local TILL_UPDATE_INTERVAL = 0.1
local TILL_START_GRACE = 2
local TILL_STOP_DELAY = 0.3
local FARM_SOIL_SPACING = 1.333

local function GetRider(beefalo)
    local rideable = beefalo.components.rideable
    return rideable ~= nil and rideable:GetRider() or nil
end

local function StopTilling(beefalo)
    local rider = beefalo._yf_tilling_rider
    local task = beefalo._yf_tilling_task

    beefalo._yf_tilling_rider = nil
    beefalo._yf_tilling_task = nil
    beefalo._yf_tilling_idle_time = nil
    beefalo._yf_tilling_has_moved = nil
    beefalo._yf_tilling_last_plot = nil

    if task ~= nil then
        task:Cancel()
    end

    if rider ~= nil and rider:IsValid() and rider.components.locomotor ~= nil then
        rider.components.locomotor:RemoveExternalSpeedMultiplier(beefalo, SPEED_MULTIPLIER_KEY)
    end

    if beefalo:IsValid()
        and beefalo.sg ~= nil
        and not beefalo.sg:HasAnyStateTag("attack", "busy", "dead") then
        beefalo.sg:GoToState("idle")
    end
end

local function RoundFarmGridSlot(offset)
    local slot = math.floor(offset / FARM_SOIL_SPACING + 0.5)
    return math.max(-1, math.min(1, slot))
end

local function GetFarmGridPoint(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    local center_x, _, center_z = TheWorld.Map:GetTileCenterPoint(x, 0, z)
    local slot_x = RoundFarmGridSlot(x - center_x)
    local slot_z = RoundFarmGridSlot(z - center_z)
    local point_x = center_x + slot_x * FARM_SOIL_SPACING
    local point_z = center_z + slot_z * FARM_SOIL_SPACING

    return Vector3(point_x, 0, point_z), string.format("%.3f:%.3f", point_x, point_z)
end

local function PlayTillingWalk(beefalo)
    if beefalo.sg == nil or beefalo.sg:HasAnyStateTag("attack", "busy", "dead") then
        return
    end

    if not beefalo.AnimState:IsCurrentAnimation("walk_loop") then
        beefalo.AnimState:PlayAnimation("walk_loop", true)
    end
end

local function UpdateTilling(beefalo)
    local rider = beefalo._yf_tilling_rider
    if rider == nil
        or not rider:IsValid()
        or GetRider(beefalo) ~= rider
        or rider.sg == nil
        or rider.sg:HasAnyStateTag("busy", "dead", "dismounting") then
        StopTilling(beefalo)
        return
    end

    if not rider.sg:HasStateTag("moving") then
        beefalo._yf_tilling_idle_time = beefalo._yf_tilling_idle_time + TILL_UPDATE_INTERVAL
        local idle_limit = beefalo._yf_tilling_has_moved and TILL_STOP_DELAY or TILL_START_GRACE
        if beefalo._yf_tilling_idle_time >= idle_limit then
            StopTilling(beefalo)
        end
        return
    end

    beefalo._yf_tilling_has_moved = true
    beefalo._yf_tilling_idle_time = 0
    PlayTillingWalk(beefalo)

    local point, plot_key = GetFarmGridPoint(beefalo)
    if plot_key == beefalo._yf_tilling_last_plot then
        return
    end

    local hunger = beefalo.components.hunger
    if hunger == nil or hunger.current < TILL_HUNGER_COST then
        StopTilling(beefalo)
        return
    end

    if beefalo.components.farmtiller == nil
        or not beefalo.components.farmtiller:Till(point, rider) then
        StopTilling(beefalo)
        return
    end

    hunger:DoDelta(-TILL_HUNGER_COST)
    beefalo._yf_tilling_last_plot = plot_key
end

local function StartTilling(rider, beefalo)
    local locomotor = rider.components.locomotor
    if locomotor == nil or beefalo.components.farmtiller == nil then
        return
    end

    beefalo._yf_tilling_rider = rider
    beefalo._yf_tilling_idle_time = 0
    beefalo._yf_tilling_has_moved = false
    beefalo._yf_tilling_last_plot = nil

    locomotor:SetExternalSpeedMultiplier(beefalo, SPEED_MULTIPLIER_KEY, TILL_SPEED_MULTIPLIER)
    beefalo._yf_tilling_task = beefalo:DoPeriodicTask(TILL_UPDATE_INTERVAL, UpdateTilling, 0)
end

local function OnTillingRequest(player)
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

    if beefalo._yf_tilling_rider == player then
        StopTilling(beefalo)
    elseif beefalo._yf_tilling_rider == nil
        and beefalo.sg ~= nil
        and not beefalo.sg:HasAnyStateTag("busy", "attack", "dead") then
        StartTilling(player, beefalo)
    end
end

AddModRPCHandler(RPC_NAMESPACE, RPC_COMMAND, OnTillingRequest)

local function OnTillingKeyDown()
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
    local key = GetModConfigData("tilling_key", true)
    if key == nil then
        key = GLOBAL.KEY_L
    end

    if key >= 0 then
        GLOBAL.TheInput:AddKeyDownHandler(key, OnTillingKeyDown)
    end
end

AddPrefabPostInit("beefalo", function(inst)
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end

    inst:AddComponent("farmtiller")
    inst:ListenForEvent("riderchanged", function(beefalo, data)
        if beefalo._yf_tilling_rider ~= nil
            and (data == nil or data.newrider ~= beefalo._yf_tilling_rider) then
            StopTilling(beefalo)
        end
    end)
end)
