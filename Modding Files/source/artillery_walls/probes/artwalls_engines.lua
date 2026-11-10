-- SPIKE: which engines of a wall battery fire (2026-11-03). Loaded over the wh3 bridge once the battle is up, after
-- artwalls_static.lua (AWS). Hypothesis under test: every engine is given its own enemy unit, and an engine whose
-- target lies outside its arc of the zone's facing neither turns nor fires.
--   AWE.zone(i, x, y, z)   occupy_zone for player unit i at a CA wall zone point, fire at will on, controller kept
--   AWE.start(name)        per-engine shot count (body +0x3e8 rising edges, 100 ms, keyed by body pointer), ammo kept up
--   AWE.report(name)       per engine: x, heading, shots, fire state; per battery: ammo
local mr = _G.memreader_plus
local AWE = _G.AWE or {}
_G.AWE = AWE
AWE.uc, AWE.runs = AWE.uc or {}, AWE.runs or {}

local VT = mr.tostring(mr.add(mr.add(mr.base, 0x3ad * 0x10000), 0xee48)) -- the engine body class (6ae2a00b; 6acec6f4: 0x3ad3360)
local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end
local function unit(i) return bm:get_player_army():units():item(i) end
local function deg(b, off) return mr.read_uint16(b, off) * 360 / 65536 end

-- the unit's list at +0x184/+0x188 holds men as well as engines (all men once the ammo runs out)
function AWE.engines(i)
	local p = obj_of(unit(i))
	local d, n, out = mr.read_pointer(p, 0x188), mr.read_int32(p, 0x184), {}
	for k = 0, n - 1 do
		local b = mr.read_pointer(d, k * 8)
		if mr.tostring(mr.read_pointer(b, 0)) == VT then out[#out + 1] = b end
	end
	return out
end

function AWE.zone(i, x, y, z)
	local u = unit(i)
	local uc = bm:get_player_army():create_unit_controller()
	uc:add_units(u)
	uc:fire_at_will(true)
	uc:occupy_zone(battle_vector:new(x, y, z), false)
	AWE.uc[i] = uc
	return u:type()
end

function AWE.start(name, units)
	local run = {shots = {}, last = {}, where = {}, since = bm:time_elapsed_ms(), units = units or {3, 4}, ammo = {}}
	for _, i in ipairs(run.units) do run.ammo[i] = unit(i):ammo_left() end
	AWE.runs[name] = run
	bm:remove_process('awe_count')
	bm:repeat_callback(function() pcall(function()
		for _, i in ipairs(run.units) do
			if unit(i):ammo_left() < 20 then unit(i):set_current_ammo_unary(1) end
			for _, b in ipairs(AWE.engines(i)) do
				local key = i .. '@' .. mr.tostring(b)
				local v = mr.read_uint16(b, 0x3e8)
				if v ~= 0 and (run.last[key] or 0) == 0 then run.shots[key] = (run.shots[key] or 0) + 1 end
				run.last[key] = v
				run.where[key] = {i = i, x = mr.read_float(b, 0x910), y = mr.read_float(b, 0x914), h = deg(b, 0xb0)}
			end
		end
	end) end, 100, 'awe_count')
	return run.since
end

-- what exe+305f9c4 reads to call an engine busy, so the planner never offers it a target: an action (+0x5c0 = 1) not
-- flagged at +0x4c8 and, with +0x324 set, whose own slot 0x40 (vtable at +0x4a8) refuses; plus the goal position
function AWE.busy(i)
	local rows = {}
	for _, b in ipairs(AWE.engines(i)) do
		rows[#rows + 1] = string.format('x%.1f has %d flag %d 324 %d vt %s goal %.1f,%.1f', mr.read_float(b, 0x910),
			mr.read_uint8(b, 0x5c0), mr.read_uint8(b, 0x4c8), mr.read_int32(b, 0x324), mr.tostring(mr.read_pointer(b, 0x4a8)),
			mr.read_float(b, 0x1e0), mr.read_float(b, 0x1e8))
	end
	return rows
end

function AWE.report(name)
	local run = AWE.runs[name]
	local rows = {}
	for key, w in pairs(run.where) do
		rows[#rows + 1] = string.format('u%d x%.1f y%.1f h%.0f shots %d', w.i, w.x, w.y, w.h, run.shots[key] or 0)
	end
	table.sort(rows)
	local foes = {}
	local us = bm:get_non_player_alliance():armies():item(1):units()
	for k = 1, us:count() do local p = us:item(k):position(); foes[#foes + 1] = string.format('(%.0f,%.0f)', p:get_x(), p:get_z()) end
	return {name = name, secs = (bm:time_elapsed_ms() - run.since) / 1000, rows = rows, foes = table.concat(foes, ' ')}
end

return 'artwalls engines probe loaded'
