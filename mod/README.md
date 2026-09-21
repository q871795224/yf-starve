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

Animation direction: reuse stock mounted-player animations first. If the rider pose proves unsuitable, then
evaluate a custom Spriter/SCML animation and compile it into `anim/`. The prototype does not add skill-tree
unlocks.

Planned script areas:

- `scripts/features/`: independent gameplay mechanisms and their development toggles.
- `scripts/components/`: reusable state, including saved player/world progress if needed.
- `scripts/prefabs/`: new equipment and mount prefabs.
- `scripts/widgets/`: skill-tree UI, added after the mechanics are validated.
