local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "mounted_charge"

local CHARGE_WINDUP_STATE = "yf_beefalo_charge_windup"
local CHARGE_DASH_STATE = "yf_beefalo_charge_dash"
local CHARGE_HIT_STATE = "yf_beefalo_charge_hit"
local CHARGE_RECOVERY_STATE = "yf_beefalo_charge_recovery"
local CHARGE_SPEED_MULTIPLIER = 1.5
local CHARGE_DURATION = 0.8
local CHARGE_COOLDOWN = 4
local CHARGE_SCAN_RADIUS = 2.5
local CHARGE_MAX_FORWARD = 2
local CHARGE_HALF_WIDTH = 1.1
local CHARGE_STALL_GRACE_TICKS = 4
local CHARGE_STALL_TICKS = 4
local CHARGE_MIN_MOVEMENT_SQ = 0.0004

local CANT_TARGET_TAGS = { "DECOR", "FX", "INLIMBO", "NOCLICK" }

local function IsMasterSim()
    return GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim
end

local function GetRider(inst)
    local rideable = inst.components.rideable
    return rideable ~= nil and rideable:GetRider() or nil
end

local function StopChargeMovement(inst)
    if inst.Physics ~= nil then
        inst.Physics:Stop()
    end

    if inst.components.locomotor ~= nil then
        inst.components.locomotor:StopMoving()
    end
end

local function LockRiderControls(inst)
    if not IsMasterSim() or inst._yf_charge_locked_rider ~= nil then
        return
    end

    local rider = GetRider(inst)
    local controller = rider ~= nil and rider.components.playercontroller or nil
    if controller ~= nil then
        inst._yf_charge_locked_rider = rider
        inst._yf_charge_controller_was_enabled = controller:IsEnabled()
        controller:Enable(false)
    end
end

local function RestoreRiderControls(inst)
    local rider = inst._yf_charge_locked_rider
    local controller = rider ~= nil and rider:IsValid() and rider.components.playercontroller or nil
    if controller ~= nil and inst._yf_charge_controller_was_enabled then
        controller:Enable(true)
    end

    inst._yf_charge_locked_rider = nil
    inst._yf_charge_controller_was_enabled = nil
end

local function ReleaseRiderControlsAfterCharge(inst)
    if not IsMasterSim() then
        return
    end

    -- The action spans several states; release input only after leaving the charge chain.
    inst:DoTaskInTime(0, function()
        if inst:IsValid() and (inst.sg == nil or not inst.sg:HasStateTag("yf_charge")) then
            RestoreRiderControls(inst)
        end
    end)
end

local function FindChargeTarget(inst)
    local combat = inst.components.combat
    if combat == nil then
        return nil
    end

    local state = inst.sg.statemem
    local x, _, z = inst.Transform:GetWorldPosition()
    local radians = state.heading * math.pi / 180
    local forward_x = math.cos(radians)
    local forward_z = -math.sin(radians)
    local rider = state.rider
    local best_target = nil
    local best_forward = math.huge

    for _, target in ipairs(TheSim:FindEntities(x, 0, z, CHARGE_SCAN_RADIUS, nil, CANT_TARGET_TAGS)) do
        if target ~= inst
            and target ~= rider
            and target:IsValid()
            and target.components.health ~= nil
            and not target.components.health:IsDead()
            and combat:CanTarget(target) then
            local target_x, _, target_z = target.Transform:GetWorldPosition()
            local dx = target_x - x
            local dz = target_z - z
            local forward = dx * forward_x + dz * forward_z
            local lateral = math.abs(dx * forward_z - dz * forward_x)

            if forward >= -0.25
                and forward <= CHARGE_MAX_FORWARD
                and lateral <= CHARGE_HALF_WIDTH
                and combat:CanHitTarget(target) then
                if forward < best_forward then
                    best_target = target
                    best_forward = forward
                end
            end
        end
    end

    return best_target
end

local function IsChargeStalled(inst)
    local state = inst.sg.statemem
    local x, _, z = inst.Transform:GetWorldPosition()
    local dx = x - state.last_x
    local dz = z - state.last_z
    local moved_sq = dx * dx + dz * dz

    state.last_x = x
    state.last_z = z
    state.dash_ticks = state.dash_ticks + 1

    if state.dash_ticks > CHARGE_STALL_GRACE_TICKS then
        if moved_sq < CHARGE_MIN_MOVEMENT_SQ then
            state.stall_ticks = state.stall_ticks + 1
        else
            state.stall_ticks = 0
        end
    end

    return state.stall_ticks >= CHARGE_STALL_TICKS
end

local function ExitChargeState(inst)
    if IsMasterSim() then
        StopChargeMovement(inst)
        ReleaseRiderControlsAfterCharge(inst)
    end
end

local function BeginDash(inst)
    inst.sg:GoToState(CHARGE_DASH_STATE)
end

AddStategraphPostInit("beefalo", function(sg)
    sg.states[CHARGE_WINDUP_STATE] = GLOBAL.State{
        name = CHARGE_WINDUP_STATE,
        tags = { "busy", "yf_charge" },

        onenter = function(inst)
            local state = inst.sg.statemem
            state.heading = inst.Transform:GetRotation()

            if IsMasterSim() then
                StopChargeMovement(inst)
                LockRiderControls(inst)
            end

            inst.AnimState:PlayAnimation("atk_pre")
            inst.sg:SetTimeout(math.max(inst.AnimState:GetCurrentAnimationLength(), 0.1))
        end,

        onupdate = function(inst)
            if IsMasterSim() then
                inst.Transform:SetRotation(inst.sg.statemem.heading)
            end
        end,

        ontimeout = BeginDash,

        events = {
            GLOBAL.EventHandler("animover", BeginDash),
        },

        onexit = ExitChargeState,
    }

    sg.states[CHARGE_DASH_STATE] = GLOBAL.State{
        name = CHARGE_DASH_STATE,
        tags = { "busy", "yf_charge" },

        onenter = function(inst)
            local state = inst.sg.statemem
            state.heading = inst.Transform:GetRotation()
            state.rider = GetRider(inst)
            state.dash_ticks = 0
            state.stall_ticks = 0

            if IsMasterSim() then
                LockRiderControls(inst)
                StopChargeMovement(inst)
                inst.Physics:SetMotorVel(TUNING.BEEFALO_RUN_SPEED * CHARGE_SPEED_MULTIPLIER, 0, 0)

                local x, _, z = inst.Transform:GetWorldPosition()
                state.last_x = x
                state.last_z = z
            end

            inst.AnimState:PlayAnimation("run_pre")
            inst.AnimState:PushAnimation("run_loop", true)
            inst.sg:SetTimeout(CHARGE_DURATION)
        end,

        onupdate = function(inst)
            if not IsMasterSim() then
                return
            end

            local state = inst.sg.statemem
            local rider = GetRider(inst)
            if rider == nil or rider ~= state.rider then
                inst.sg:GoToState(CHARGE_RECOVERY_STATE)
                return
            end

            inst.Transform:SetRotation(state.heading)

            local target = FindChargeTarget(inst)
            if target ~= nil then
                inst.components.combat:DoAttack(target)
                inst.sg:GoToState(CHARGE_HIT_STATE)
                return
            end

            if IsChargeStalled(inst) then
                inst.sg:GoToState(CHARGE_RECOVERY_STATE)
            end
        end,

        ontimeout = function(inst)
            inst.sg:GoToState(CHARGE_RECOVERY_STATE)
        end,

        onexit = ExitChargeState,
    }

    local function MakeRecoveryState(name, animation)
        return GLOBAL.State{
            name = name,
            tags = { "busy", "yf_charge" },

            onenter = function(inst)
                if IsMasterSim() then
                    LockRiderControls(inst)
                    StopChargeMovement(inst)
                end

                inst.AnimState:PlayAnimation(animation)
                inst.sg:SetTimeout(math.max(inst.AnimState:GetCurrentAnimationLength(), 0.1))
            end,

            ontimeout = function(inst)
                inst.sg:GoToState("idle")
            end,

            events = {
                GLOBAL.EventHandler("animover", function(inst)
                    inst.sg:GoToState("idle")
                end),
            },

            onexit = ExitChargeState,
        }
    end

    sg.states[CHARGE_HIT_STATE] = MakeRecoveryState(CHARGE_HIT_STATE, "atk")
    sg.states[CHARGE_RECOVERY_STATE] = MakeRecoveryState(CHARGE_RECOVERY_STATE, "run_pst")
end)

local function StartCooldown(beefalo)
    beefalo._yf_beefalo_charge_cooldown = true
    beefalo:DoTaskInTime(CHARGE_COOLDOWN, function()
        if beefalo:IsValid() then
            beefalo._yf_beefalo_charge_cooldown = nil
        end
    end)
end

local function OnChargeRequest(player)
    print("[yf-starve] RPC received: mounted_charge")

    if player == nil or not player:IsValid() then
        print("[yf-starve] mounted_charge rejected: invalid player")
        return
    end

    local rider = player.components.rider
    if rider == nil or not rider:IsRiding() then
        print("[yf-starve] mounted_charge rejected: player is not riding")
        return
    end

    if player.sg == nil or player.sg:HasStateTag("busy") then
        print("[yf-starve] mounted_charge rejected: player is busy")
        return
    end

    local beefalo = rider:GetMount()
    if beefalo == nil or not beefalo:IsValid() or beefalo.prefab ~= "beefalo" then
        print("[yf-starve] mounted_charge rejected: mount is not a valid beefalo")
        return
    end

    if beefalo.sg == nil then
        print("[yf-starve] mounted_charge rejected: beefalo has no stategraph")
        return
    end

    if beefalo.sg:HasStateTag("busy") then
        print("[yf-starve] mounted_charge rejected: beefalo is busy")
        return
    end

    if beefalo.sg:HasStateTag("attack") then
        print("[yf-starve] mounted_charge rejected: beefalo is attacking")
        return
    end

    if beefalo._yf_beefalo_charge_cooldown then
        print("[yf-starve] mounted_charge rejected: cooldown is active")
        return
    end

    StartCooldown(beefalo)
    print("[yf-starve] mounted_charge accepted: entering windup")
    beefalo.sg:GoToState(CHARGE_WINDUP_STATE)
end

AddModRPCHandler(RPC_NAMESPACE, RPC_COMMAND, OnChargeRequest)

local function OnChargeKeyDown()
    print("[yf-starve] keydown: mounted_charge")

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

    print("[yf-starve] sending RPC: mounted_charge")
    GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][RPC_COMMAND])
end

if not GLOBAL.TheNet:IsDedicated() then
    local key = GetModConfigData("charge_key", true)
    if key == nil then
        key = GLOBAL.KEY_J
    end

    if key >= 0 then
        GLOBAL.TheInput:AddKeyDownHandler(key, OnChargeKeyDown)
        print("[yf-starve] registered mounted_charge key handler:", key)
    end
end
