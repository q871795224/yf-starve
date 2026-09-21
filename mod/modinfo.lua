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
}
