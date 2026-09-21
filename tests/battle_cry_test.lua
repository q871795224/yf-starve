-- Run from the repository root with: luajit tests/battle_cry_test.lua
-- This verifies mounted-player state selection and animation dispatch, not rendering.

local RPC_NAMESPACE = "yf_starve_beefalo_skill_system"
local RPC_COMMAND = "battle_cry"
local BATTLE_CRY_STATE = "yf_mounted_battle_cry"
local expected_rpc = {}
local registered_key
local key_handler
local server_handler
local sent_rpc = 0
local go_to_state_calls = 0
local riding = true
local player_state_tags = {}
local mount_state_tags = {}
local current_animation
local mount_sound_count = 0
local stategraphs = {}
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

local beefalo = { prefab = "beefalo", sounds = { grunt = "beefalo_grunt" } }
function beefalo:IsValid()
    return true
end
beefalo.SoundEmitter = {
    PlaySound = function(_, sound)
        assert(sound == "beefalo_grunt", "battle cry played the wrong mount sound")
        mount_sound_count = mount_sound_count + 1
    end,
}
beefalo.sg = {
    currentstate = { name = "idle" },
    HasStateTag = function(_, tag)
        return mount_state_tags[tag] == true
    end,
}

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
        locomotor = {
            StopMoving = function() end,
        },
    },
    AnimState = {
        PlayAnimation = function(_, animation)
            current_animation = animation
        end,
        IsCurrentAnimation = function(_, animation)
            return current_animation == animation
        end,
        AnimDone = function()
            return false
        end,
    },
}
function player:IsValid()
    return true
end
player.sg = {
    currentstate = { name = "idle" },
    HasStateTag = function(_, tag)
        return player_state_tags[tag] == true
    end,
    GoToState = function(self, state)
        go_to_state_calls = go_to_state_calls + 1
        self.currentstate = { name = state }
        local definition = stategraphs.wilson.states[state]
        assert(definition ~= nil, "server battle cry state was not registered")
        definition.onenter(player)
    end,
}

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
    State = function(definition) return definition end,
    EventHandler = function(name, fn) return { name = name, fn = fn } end,
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
_G.AddStategraphPostInit = function(name, callback)
    local sg = { states = {} }
    callback(sg)
    stategraphs[name] = sg
end

dofile("mod/scripts/features/battle_cry.lua")

assert(registered_key == 104, "default H key was not registered")
assert(key_handler ~= nil, "key handler was not registered")
assert(server_handler ~= nil, "server RPC handler was not registered")
assert(stategraphs.wilson.states[BATTLE_CRY_STATE] ~= nil, "server mounted battle cry state was not registered")
assert(stategraphs.wilson_client.states[BATTLE_CRY_STATE] ~= nil, "client mounted battle cry state was not registered")

key_handler()
assert(sent_rpc == 1, "H did not send the battle cry RPC")
assert(go_to_state_calls == 1, "valid rider did not enter the custom battle cry state")
assert(player.sg.currentstate.name == BATTLE_CRY_STATE, "battle cry did not transition the rider")
assert(current_animation == "bellow", "battle cry did not play bellow on the rider AnimState")
assert(mount_sound_count == 1, "battle cry did not play the beefalo grunt")

key_handler()
assert(sent_rpc == 2, "repeat H did not reach the RPC handler")
assert(go_to_state_calls == 1, "repeat H restarted the battle cry animation")
assert(mount_sound_count == 1, "repeat H replayed the battle cry sound")

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

player.sg.currentstate = { name = "idle" }
player_state_tags.busy = true
server_handler(player)
assert(go_to_state_calls == 1, "busy rider triggered the battle cry")
player_state_tags.busy = nil

riding = false
server_handler(player)
assert(go_to_state_calls == 1, "non-rider triggered the battle cry")
riding = true

mount_state_tags.busy = true
server_handler(player)
assert(go_to_state_calls == 1, "busy beefalo triggered the battle cry")
mount_state_tags.busy = nil

mount_state_tags.attack = true
server_handler(player)
assert(go_to_state_calls == 1, "attacking beefalo triggered the battle cry")
mount_state_tags.attack = nil

beefalo.prefab = "koalefant"
server_handler(player)
assert(go_to_state_calls == 1, "non-beefalo mount triggered the battle cry")

print("battle_cry_test: mounted-player animation checks passed")
