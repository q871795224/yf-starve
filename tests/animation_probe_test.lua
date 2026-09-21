-- Run from the repository root with: luajit tests/animation_probe_test.lua

local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local server_handlers = {}
local key_handler
local go_to_state_calls = {}
local sent_rpcs = 0
local mounted = true
local nearby = {}
local active_screen
local chat_open = false
local console_open = false
local pushed_event
local local_animation

local hud = {}
function hud:IsChatInputScreenOpen()
    return chat_open
end
function hud:IsConsoleScreenOpen()
    return console_open
end

local beefalo = {
    prefab = "beefalo",
    components = { health = { IsDead = function() return false end } },
    Transform = { GetWorldPosition = function() return 2, 0, 0 end },
    AnimState = {
        PlayAnimation = function(_, animation)
            local_animation = animation
        end,
    },
    sg = { currentstate = { name = "idle" } },
}
function beefalo:IsValid()
    return true
end
function beefalo.sg:GoToState(state)
    go_to_state_calls[#go_to_state_calls + 1] = state
    self.currentstate = { name = state }
end
function beefalo:PushEvent(event, data)
    pushed_event = { event = event, data = data }
    if event == "heardhorn" and data ~= nil and data.musician ~= nil then
        self.sg:GoToState("bellow")
    end
end

local player = {
    HUD = hud,
    Transform = { GetWorldPosition = function() return 0, 0, 0 end },
    components = {
        rider = {
            GetMount = function()
                return mounted and beefalo or nil
            end,
        },
    },
    replica = {
        rider = {
            GetMount = function()
                return mounted and beefalo or nil
            end,
        },
    },
}
function player:IsValid()
    return true
end

active_screen = hud
_G.GLOBAL = {
    KEY_F10 = 291,
    TheNet = { IsDedicated = function() return false end },
    TheInput = {
        AddKeyDownHandler = function(_, key, callback)
            assert(key == 291, "animation probes did not use F10")
            key_handler = callback
        end,
    },
    TheFrontEnd = { GetActiveScreen = function() return active_screen end },
    SendModRPCToServer = function(rpc)
        sent_rpcs = sent_rpcs + 1
        assert(server_handlers[rpc] ~= nil, "animation probe sent an unregistered RPC")
        server_handlers[rpc](player)
    end,
    ThePlayer = player,
}
_G.MOD_RPC = { [RPC_NAMESPACE] = {} }
_G.TheSim = {
    FindEntities = function()
        return nearby
    end,
}
_G.AddModRPCHandler = function(namespace, command, callback)
    assert(namespace == RPC_NAMESPACE)
    server_handlers[command] = callback
    MOD_RPC[namespace][command] = command
end

dofile("mod/scripts/features/animation_probe.lua")
assert(key_handler ~= nil, "F10 animation probe key was not registered")

key_handler()
assert(go_to_state_calls[#go_to_state_calls] == "bellow", "first F10 probe did not enter bellow directly")

key_handler()
assert(pushed_event.event == "heardhorn", "second F10 probe did not send heardhorn")
assert(pushed_event.data.musician == player, "heardhorn event did not include the player")
assert(go_to_state_calls[#go_to_state_calls] == "bellow", "heardhorn event did not enter bellow")

key_handler()
assert(go_to_state_calls[#go_to_state_calls] == "shake", "third F10 probe did not enter shake")
key_handler()
assert(go_to_state_calls[#go_to_state_calls] == "matingcall", "fourth F10 probe did not enter matingcall")

mounted = false
nearby = { beefalo }
key_handler()
assert(go_to_state_calls[#go_to_state_calls] == "graze", "fifth F10 probe did not target a nearby beefalo")

local rpcs_before_local_probes = sent_rpcs
key_handler()
assert(local_animation == "bellow", "sixth F10 probe did not play local bellow")
key_handler()
assert(local_animation == "mating_taunt1", "seventh F10 probe did not play local mating taunt")
assert(sent_rpcs == rpcs_before_local_probes, "client-local probes sent server RPCs")

key_handler()
assert(go_to_state_calls[#go_to_state_calls] == "actual_alert", "eighth F10 probe did not enter actual_alert")

local calls_before_rejected_input = sent_rpcs
chat_open = true
key_handler()
assert(sent_rpcs == calls_before_rejected_input, "F10 sent an RPC while chat was open")
chat_open = false

nearby = {}
local states_before_missing_target = #go_to_state_calls
key_handler()
assert(#go_to_state_calls == states_before_missing_target, "probe acted without a nearby beefalo")

print("animation_probe_test: 14 checks passed")
