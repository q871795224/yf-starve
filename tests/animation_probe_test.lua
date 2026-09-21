-- Run from the repository root with: luajit tests/animation_probe_test.lua
-- F10 is a single mounted-player animation probe; it no longer cycles beefalo entities.

local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"
local expected_rpc = {}
local registered_key
local key_handler
local sent_rpc = 0
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

local player = { HUD = hud }
active_screen = hud

_G.GLOBAL = {
    KEY_F10 = 291,
    TheNet = { IsDedicated = function() return false end },
    TheInput = {
        AddKeyDownHandler = function(_, key, callback)
            registered_key = key
            key_handler = callback
        end,
    },
    TheFrontEnd = { GetActiveScreen = function() return active_screen end },
    SendModRPCToServer = function(rpc)
        assert(rpc == expected_rpc, "F10 sent the wrong RPC")
        sent_rpc = sent_rpc + 1
    end,
    ThePlayer = player,
}
_G.MOD_RPC = { [RPC_NAMESPACE] = { [RPC_COMMAND] = expected_rpc } }

dofile("mod/scripts/features/animation_probe.lua")

assert(registered_key == 291, "F10 animation probe key was not registered")
assert(key_handler ~= nil, "F10 animation probe handler was not registered")

key_handler()
assert(sent_rpc == 1, "F10 did not request the mounted-player battle cry")

active_screen = {}
key_handler()
assert(sent_rpc == 1, "F10 sent an RPC outside the HUD")
active_screen = hud

chat_open = true
key_handler()
assert(sent_rpc == 1, "F10 sent an RPC while chat was open")
chat_open = false

console_open = true
key_handler()
assert(sent_rpc == 1, "F10 sent an RPC while the console was open")

print("animation_probe_test: F10 mounted-player path checks passed")
