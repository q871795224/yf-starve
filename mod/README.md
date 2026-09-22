# Mod package

This directory is the payload intended for local DST loading and, eventually, Steam Workshop upload.
Project notes and reference mods live outside this directory so they do not get packaged by mistake.

The API version and client/server settings have not been runtime-verified. The first standalone mechanism is
mounted attack sync: after a ridden beefalo emits `onattackother`, the rider enters a custom state in the
`wilson` stategraph. It plays the existing `player_atk_pre` / `player_atk` mounted-player animations and
calls the rider's `combat:DoAttack(target)` at frame 10 with the same equipped non-projectile weapon. The
beefalo and rider still resolve two separate hits; the rider's hit is delayed to the animation timeline.
The matching `wilson_client` state is registered for the visual. No local game test is planned, so the
animation names, exact hit frame, and multiplayer presentation remain unverified.

Mounted battle cry is a second standalone prototype. The client key (default H, configurable in the mod
settings) asks the server to put the rider into a short custom state. While riding, the player's animation
bank is `wilsonbeefalo`; the stock `player_mount.zip` includes the `bellow` clip. The rider state plays that
clip and the beefalo grunt. It has no fear or combat effect and adds no animation assets. F10 triggers the
same rider animation for testing. This bypasses the vanilla `heardhorn` event, which changes the beefalo
entity's state but does not animate the mounted rider bank.

Mounted charge is a third standalone prototype. The client key (default J, configurable in the mod settings)
asks the server to run a short, straight charge. It reuses the beefalo's `atk_pre`, `run_pre`, `run_loop`, `atk`,
and `run_pst` animations, disables rider controls during the action, and attacks the first valid target in its
path once using normal beefalo damage. A blocked charge or timeout ends in recovery; the prototype uses a 1.5x
run-speed multiplier, a 0.8-second dash limit, and a 4-second cooldown. If mounted attack sync is active and the
rider has a melee weapon, the existing rider attack also follows the beefalo's hit. No custom animation assets
were added. Validate animation transitions, control lock, collision handling, cooldown, and multiplayer behavior
in-game before balancing these prototype values.

Mounted tilling is a fourth standalone prototype. The configurable key (default L) starts or cancels a manual
plowing pass. While the rider steers, movement is slowed to 0.35x and the beefalo plays its existing `walk_loop`
animation. Each new farm-grid position is tilled through the vanilla `FarmTiller` component and costs 4 beefalo
hunger. The pass ends after movement stops, the rider dismounts, the current position cannot be tilled, or the
beefalo cannot pay the hunger cost. No custom animation assets were added. Validate grid alignment, movement
speed, animation transitions, hunger cost, and multiplayer behavior in-game before balancing it.

Mounted lance is a fifth standalone prototype. The configurable key (default B) is available while riding a
beefalo and plays a custom 23-frame `wilsonbeefalo` sequence: the rider leans with the vanilla beefalo attack,
the lance travels forward and follows the upward thrust, and the original grip hands stay in front of the weapon.
The resources are `anim/yf_mounted_lance.zip` (three added clips) and the small official `swap_spear_lance` build.
This first game pass is visual only: it intentionally does not call `combat:DoAttack`, so we can compare the
mounted timing and layering without adding a second hit to the vanilla beefalo attack. It uses the side-facing
variant for the first in-game pass; damage, directional variants, and the lance equipment rule come afterward.

Animation direction: reuse stock mounted-player animations first. The battle cry uses the existing mounted
`bellow` clip. If a later skill needs a pose that is absent from the mounted bank, evaluate a custom
Spriter/SCML animation and compile it into `anim/`. The prototype does not add skill-tree unlocks.

Planned script areas:

- `scripts/features/`: independent gameplay mechanisms and their development toggles.
- `scripts/components/`: reusable state, including saved player/world progress if needed.
- `scripts/prefabs/`: new equipment and mount prefabs.
- `scripts/widgets/`: skill-tree UI, added after the mechanics are validated.
