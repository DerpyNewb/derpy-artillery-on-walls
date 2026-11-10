-- SPIKE: why a wall battery holds fire (2026-11-01 22:20). Loaded over the wh3 bridge once Deployed, after
-- artwalls_probe.lua (AW) and artwalls_items.lua (AWI). Three questions, one variable each:
--   AWF.headings(i, target)   per engine: position, heading in degrees, bearing to the target, the offset between them
--   AWF.watch(i, name, secs)  ammo every 5 s into AWF.rows[name], plus the mover's recovery count read off the log tail
--   AWF.face(i, target)       teleport the unit onto its own centre, facing the target (rotates every engine in place)
local mr = _G.memreader_plus
local AWF = _G.AWF or {}
_G.AWF = AWF

local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end
local function unit(i) return bm:get_player_army():units():item(i) end

local function bearing(x0, z0, x1, z1) return math.deg(math.atan2(x1 - x0, z1 - z0)) % 360 end

function AWF.headings(i, target)
	local p = obj_of(unit(i))
	local d, n = mr.read_pointer(p, 0x188), mr.read_int32(p, 0x184)
	local tp = target:position()
	local out = {}
	for k = 0, n - 1 do
		local b = mr.read_pointer(d, k * 8)
		local x, y, z = mr.read_float(b, 0x910), mr.read_float(b, 0x914), mr.read_float(b, 0x918)
		local h = mr.read_uint16(b, 0xb0) * 360 / 65536
		local br = bearing(x, z, tp:get_x(), tp:get_z())
		local off = math.abs(h - br); off = math.min(off, 360 - off)
		out[#out + 1] = string.format('e%d %.0f,%.1f,%.0f heading %.0f bearing %.0f off %.0f wall %d', k + 1, x, y, z, h, br, off, mr.is_null(mr.read_pointer(b, 0x920)) and 0 or 1)
	end
	return out
end

function AWF.watch(i, name, secs)
	AWF.rows = AWF.rows or {}
	AWF.rows[name] = {}
	local t0 = bm:time_elapsed_ms()
	bm:remove_process('awf_' .. name)
	bm:repeat_callback(function()
		local now = bm:time_elapsed_ms()
		AWF.rows[name][#AWF.rows[name] + 1] = string.format('%d ammo %d', now - t0, unit(i):ammo_left())
		if now - t0 >= secs * 1000 then bm:remove_process('awf_' .. name) end
	end, 5000, 'awf_' .. name)
	return 'watching ' .. name
end

function AWF.face(i, target)
	local u = unit(i)
	local pos, tp = u:position(), target:position()
	local br = bearing(pos:get_x(), pos:get_z(), tp:get_x(), tp:get_z())
	local c = bm:get_player_army():create_unit_controller()
	c:add_units(u); c:take_control(); c:halt()
	c:teleport_to_location(battle_vector:new(pos:get_x(), 0, pos:get_z()), br, u:ordered_width())
	c:release_control()
	return string.format('faced %.0f at %.0f,%.0f', br, pos:get_x(), pos:get_z())
end

return 'fire probe loaded'
