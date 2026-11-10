-- Test set-up for a live battle (author's rule, 2026-11-03): the enemy held still and immune to damage, the
-- player's units invincible but still under the player's orders. Load once the battle is up, before ordering:
--   local f = assert(loadfile('G:/Modding for resources/Modding Files/source/artillery_walls/probes/artwalls_static.lua')); setfenv(f, getfenv(1)); return f()
-- AWS.place(x, z, spread) moves the held enemy to a line in front of the wall; AWS.hold() halts it again.
local AWS = _G.AWS or {}
_G.AWS = AWS

-- the controllers live in this global, or they are collected and the enemy is handed back to its AI
AWS.enemy, AWS.mine = {}, {}

local function each(army, fn)
	local us = army:units()
	for i = 1, us:count() do fn(us:item(i), army) end
end

local function foes(fn)
	local armies = bm:get_non_player_alliance():armies()
	for a = 1, armies:count() do each(armies:item(a), fn) end
end

function AWS.hold()
	for _, uc in ipairs(AWS.enemy) do uc:halt() end
	return #AWS.enemy
end

function AWS.place(x, z, spread)
	for k, uc in ipairs(AWS.enemy) do
		uc:teleport_to_location(battle_vector:new(x + (k - (#AWS.enemy + 1) / 2) * spread, 0, z), 0, 20)
	end
	return AWS.hold()
end

foes(function(u, army)
	local uc = army:create_unit_controller()
	uc:add_units(u)
	uc:take_control()
	uc:set_invincible(true)
	uc:morale_behavior_fearless()
	uc:halt()
	AWS.enemy[#AWS.enemy + 1] = uc
end)
each(bm:get_player_army(), function(u, army)
	local uc = army:create_unit_controller()
	uc:add_units(u)
	uc:set_invincible(true)
	uc:morale_behavior_fearless()
	uc:release_control()
	AWS.mine[#AWS.mine + 1] = uc
end)
return string.format('held %d enemy units, shielded %d of mine', #AWS.enemy, #AWS.mine)
