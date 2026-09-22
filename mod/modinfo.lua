name = "Beefalo Skill System (Development)"
description = "Development scaffold for a beefalo riding mod."
author = "yf-starve"
version = "0.1.0-dev"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false

all_clients_require_mod = true
client_only_mod = false

configuration_options =
{
    {
        name = "battle_cry_key",
        label = "战吼按键",
        hover = "骑乘牛时触发战吼演出。",
        options =
        {
            { description = "H", data = 104 },
            { description = "R", data = 114 },
            { description = "V", data = 118 },
            { description = "关闭", data = -1 },
        },
        default = 104,
        client = true,
    },
    {
        name = "charge_key",
        label = "蓄力冲撞按键",
        hover = "骑乘牛时发动直线蓄力冲撞。",
        options =
        {
            { description = "J", data = 106 },
            { description = "K", data = 107 },
            { description = "N", data = 110 },
            { description = "关闭", data = -1 },
        },
        default = 106,
        client = true,
    },
    {
        name = "tilling_key",
        label = "牛牛犁地按键",
        hover = "骑乘牛时启动或停止沿途耕地。",
        options =
        {
            { description = "L", data = 108 },
            { description = "U", data = 117 },
            { description = "I", data = 105 },
            { description = "关闭", data = -1 },
        },
        default = 108,
        client = true,
    },
    {
        name = "lance_key",
        label = "骑枪演示按键",
        hover = "骑乘牛时播放 23 帧骑枪刺击动作（当前仅演示动画，不造成额外伤害）。",
        options =
        {
            { description = "B", data = 98 },
            { description = "M", data = 109 },
            { description = "O", data = 111 },
            { description = "关闭", data = -1 },
        },
        default = 98,
        client = true,
    },
}
