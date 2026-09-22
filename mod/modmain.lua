-- DST mod entry point.

Assets = {
    Asset("ANIM", "bank/yf_mounted_lance.zip"),
    Asset("ANIM", "anim/swap_spear_lance.zip"),
}

modimport("scripts/features/mounted_attack_sync.lua")
modimport("scripts/features/battle_cry.lua")
modimport("scripts/features/animation_probe.lua")
modimport("scripts/features/mounted_charge.lua")
modimport("scripts/features/mounted_tilling.lua")
modimport("scripts/features/mounted_lance.lua")
