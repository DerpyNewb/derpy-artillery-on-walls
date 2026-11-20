# Changelog

## 2026-11-12

Pack `A041`, same game build.

- Guns drawn by an animal can now go on walls: Cathay's guns, Ogre artillery, Little Grom and Empire War Wagons.
  They stand in the middle of the walkway, read from the wall section's `central_position()`, instead of at the
  parapet, where the animal has no room. CA's hover preview still shows them at the parapet.

## 2026-11-11

Pack `1A09`, same game build.

- Attacking artillery can shoot the walls again. A listed gun was infantry to CA's wall order, so an attacker's
  right-click on an enemy wall stopped being an attack.
- Only the side holding the walls can put guns on them. The owner is read from the gates at load (plain wall sections
  own nothing), not from `is_attacker()`, because in a sally battle the garrison is the attacker.

## 2026-11-10, first release

Workshop item 3837212899, pack `A862`, for game build 6ae2a00b (patch 9.0.5).

- Artillery and gun war machines can stand on settlement walls in siege battles: 50 vanilla units, plus modded
  artillery. Animal-drawn guns stay on the ground.
- Guns on a wall turn all the way round and fire, including at enemies inside the city.
- Batteries pass each other on the walkway; enemy shots still see a gun at full size.
- The AI is allowed to put artillery on walls.
- Single player only. Switches itself off in multiplayer and on any other game build.
