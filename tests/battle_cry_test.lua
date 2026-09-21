-- Run from the repository root with: luajit tests/battle_cry_test.lua
-- This checks input/RPC/state selection with stubs, not DST animation rendering.

local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"
local expected_rpc = {}
local registered_key
local key_handler
local server_handler
local sent_rpc = 0
local go_to_state_calls = 0
local riding = true
local tags = {}
local active_screen
local chat_open = false
local console_open = false

local hud = {}
function hud:IsChatInputScreenOpen()
    return chat_open
end
function hud:IsConsoleScreenOpen()
    return console_open
end

local beefalo = { prefab = "beefalo" }
function beefalo:IsValid()
    return true
end

beefalo.sg = {}
function beefalo.sg:HasStateTag(tag)
    return tags[tag] == true
end
function beefalo.sg:GoToState(state)
    go_to_state_calls = go_to_state_calls + 1
    self.currentstate = { name = state }
end

local player = {
    HUD = hud,
    components = {
        rider = {
            IsRiding = function()
                return riding
            end,
            GetMount = function()
                return beefalo
            end,
        },
    },
}
function player:IsValid()
    return true
end

active_screen = hud
_G.GLOBAL = {
    KEY_H = 104,
    TheNet = { IsDedicated = function() return false end },
    TheInput = {
        AddKeyDownHandler = function(_, key, callback)
            registered_key = key
            key_handler = callback
        end,
    },
    TheFrontEnd = { GetActiveScreen = function() return active_screen end },
    SendModRPCToServer = function(rpc)
        assert(rpc == expected_rpc, "hotkey sent the wrong RPC")
        sent_rpc = sent_rpc + 1
        server_handler(player)
    end,
    ThePlayer = player,
}
_G.MOD_RPC = { [RPC_NAMESPACE] = { [RPC_COMMAND] = expected_rpc } }
_G.GetModConfigData = function()
    return nil
end
_G.AddModRPCHandler = function(namespace, command, callback)
    assert(namespace == RPC_NAMESPACE)
    assert(command == RPC_COMMAND)
    server_handler = callback
end

dofile("mod/scripts/features/battle_cry.lua")

assert(registered_key == 104, "default H key was not registered")
assert(key_handler ~= nil, "key handler was not registered")
assert(server_handler ~= nil, "server RPC handler was not registered")

key_handler()
assert(sent_rpc == 1, "H did not send the battle cry RPC")
assert(go_to_state_calls == 1, "valid rider did not trigger the state")
assert(beefalo.sg.currentstate.name == "bellow", "valid rider did not enter vanilla bellow")

key_handler()
assert(sent_rpc == 2, "repeat H did not reach the RPC handler")
assert(go_to_state_calls == 1, "repeat H restarted the bellow animation")

active_screen = {}
key_handler()
assert(sent_rpc == 2, "hotkey sent an RPC while outside the HUD")
active_screen = hud

chat_open = true
key_handler()
assert(sent_rpc == 2, "hotkey sent an RPC while chat was open")
chat_open = false

console_open = true
key_handler()
assert(sent_rpc == 2, "hotkey sent an RPC while the console was open")
console_open = false

riding = false
server_handler(player)
assert(go_to_state_calls == 1, "non-rider triggered the state")
riding = true

tags.busy = true
server_handler(player)
assert(go_to_state_calls == 1, "busy beefalo triggered the state")
tags.busy = nil

tags.attack = true
server_handler(player)
assert(go_to_state_calls == 1, "attacking beefalo triggered the state")
tags.attack = nil

beefalo.prefab = "koalefant"
server_handler(player)
assert(go_to_state_calls == 1, "non-beefalo mount triggered the state")

print("battle_cry_test: 15 checks passed")
