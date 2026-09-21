local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local PROBE_RADIUS = 8
local next_probe_index = 1

local PROBES = {
    { rpc = "animation_probe_bellow", label = "direct bellow state", state = "bellow", animation = "bellow" },
    { label = "client-local bellow clip", local_animation = "bellow" },
    { rpc = "animation_probe_heardhorn", label = "vanilla heardhorn event", event = "heardhorn", animation = "bellow" },
    { label = "client-local mating taunt clip", local_animation = "mating_taunt1" },
    { rpc = "animation_probe_shake", label = "shake", state = "shake", animation = "shake" },
    { rpc = "animation_probe_matingcall", label = "mating call", state = "matingcall", animation = "mating_taunt1" },
    { rpc = "animation_probe_graze", label = "graze", state = "graze", animation = "graze_loop" },
    { rpc = "animation_probe_alert", label = "head-raised alert idle", state = "actual_alert", animations = { "alert_pre", "alert_idle" } },
}

local function IsValidBeefalo(inst)
    return inst ~= nil
        and inst:IsValid()
        and inst.prefab == "beefalo"
        and inst.sg ~= nil
end

local function IsProbeAnimationActive(inst, probe)
    if probe.animation ~= nil then
        return inst.AnimState:IsCurrentAnimation(probe.animation)
    end

    for _, animation in ipairs(probe.animations or {}) do
        if inst.AnimState:IsCurrentAnimation(animation) then
            return true
        end
    end

    return false
end

local function FindTargetBeefalo(player)
    local rider = player.components.rider
    local mount = rider ~= nil and rider:GetMount() or nil
    if IsValidBeefalo(mount) then
        return mount, "mounted"
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local closest = nil
    local closest_distance_sq = PROBE_RADIUS * PROBE_RADIUS

    for _, candidate in ipairs(TheSim:FindEntities(x, y, z, PROBE_RADIUS, { "beefalo" }, { "INLIMBO", "NOCLICK" })) do
        if IsValidBeefalo(candidate)
            and (candidate.components.health == nil or not candidate.components.health:IsDead()) then
            local candidate_x, candidate_y, candidate_z = candidate.Transform:GetWorldPosition()
            local dx = candidate_x - x
            local dy = candidate_y - y
            local dz = candidate_z - z
            local distance_sq = dx * dx + dy * dy + dz * dz

            if distance_sq <= closest_distance_sq then
                closest = candidate
                closest_distance_sq = distance_sq
            end
        end
    end

    return closest, "nearby"
end

local function FindLocalTargetBeefalo(player)
    local rider = player.replica ~= nil and player.replica.rider or nil
    local mount = rider ~= nil and rider:GetMount() or nil
    if mount ~= nil and mount:IsValid() and mount.prefab == "beefalo" and mount.AnimState ~= nil then
        return mount, "mounted"
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local closest = nil
    local closest_distance_sq = PROBE_RADIUS * PROBE_RADIUS

    for _, candidate in ipairs(TheSim:FindEntities(x, y, z, PROBE_RADIUS, { "beefalo" }, { "INLIMBO", "NOCLICK" })) do
        if candidate:IsValid() and candidate.prefab == "beefalo" and candidate.AnimState ~= nil then
            local candidate_x, candidate_y, candidate_z = candidate.Transform:GetWorldPosition()
            local dx = candidate_x - x
            local dy = candidate_y - y
            local dz = candidate_z - z
            local distance_sq = dx * dx + dy * dy + dz * dz

            if distance_sq <= closest_distance_sq then
                closest = candidate
                closest_distance_sq = distance_sq
            end
        end
    end

    return closest, "nearby"
end

local function OnAnimationProbeRequest(player, probe)
    if player == nil or not player:IsValid() then
        print("[yf-starve] animation_probe rejected: invalid player")
        return
    end

    local beefalo, target_source = FindTargetBeefalo(player)
    if beefalo == nil then
        print("[yf-starve] animation_probe rejected: no beefalo within", PROBE_RADIUS, "units")
        return
    end

    if probe.event ~= nil then
        beefalo:PushEvent(probe.event, { musician = player })
    else
        beefalo.sg:GoToState(probe.state)
    end

    local state = beefalo.sg.currentstate
    print("[yf-starve] animation_probe applied:", probe.label,
        "target:", target_source,
        "state:", state ~= nil and state.name or "unknown",
        "animation_active:", IsProbeAnimationActive(beefalo, probe))

    if probe.animation ~= nil or probe.animations ~= nil then
        beefalo:DoTaskInTime(0.2, function(inst)
            if inst:IsValid() then
                local current_state = inst.sg ~= nil and inst.sg.currentstate or nil
                print("[yf-starve] animation_probe server followup:", probe.label,
                    "target:", target_source,
                    "state:", current_state ~= nil and current_state.name or "unknown",
                    "animation_active:", IsProbeAnimationActive(inst, probe))
            end
        end)
    end

end

local function RegisterServerProbe(probe)
    if probe.rpc ~= nil then
        AddModRPCHandler(RPC_NAMESPACE, probe.rpc, function(player)
            OnAnimationProbeRequest(player, probe)
        end)
    end
end

for _, probe in ipairs(PROBES) do
    RegisterServerProbe(probe)
end

if not GLOBAL.TheNet:IsDedicated() then
    GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_F10, function()
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

        local probe = PROBES[next_probe_index]
        next_probe_index = next_probe_index % #PROBES + 1
        print("[yf-starve] animation_probe F10:", probe.label)

        if probe.local_animation ~= nil then
            local beefalo, target_source = FindLocalTargetBeefalo(player)
            if beefalo == nil then
                print("[yf-starve] animation_probe local rejected: no beefalo within", PROBE_RADIUS, "units")
                return
            end

            beefalo.AnimState:PlayAnimation(probe.local_animation)
            print("[yf-starve] animation_probe played locally:", probe.local_animation,
                "target:", target_source,
                "animation_active:", beefalo.AnimState:IsCurrentAnimation(probe.local_animation))
            player:DoTaskInTime(0.2, function()
                if beefalo:IsValid() then
                    print("[yf-starve] animation_probe client followup:", probe.local_animation,
                        "target:", target_source,
                        "animation_active:", beefalo.AnimState:IsCurrentAnimation(probe.local_animation))
                end
            end)
        else
            GLOBAL.SendModRPCToServer(MOD_RPC[RPC_NAMESPACE][probe.rpc])
        end
    end)

    print("[yf-starve] registered animation_probe: F10 cycles through", #PROBES, "probes")
end
