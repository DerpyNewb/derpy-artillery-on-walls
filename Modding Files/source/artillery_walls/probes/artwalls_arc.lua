-- SPIKE: the one-engine-fires problem (2026-11-02). With `noarc` in, a wall battery never re-faces, so only the engine
-- whose heading already matches the bearing fires. Question: does an engine standing in a native wall slot turn in
-- place to follow its slot's facing, and does the whole battery then fire? Loaded over the wh3 bridge, in a battle,
-- after artwalls_probe.lua (AW); needs AWT.uc[i] controllers and AWT.enemy[1] from the deployed setup.
--   AWA.zone_of(i)           zone, surface and first slot point off unit i's wall controller (a unit deployed on a wall has one)
--   AWA.wall_order(i, t)     the native wall order (DEFEND_BATTLEFIELD_ZONE) for unit i at t = {zone=, surface=, x=, z=}
--   AWA.slots(i)             per slot of unit i's wall controller: body, point, row, row facing, body heading
--   AWA.face(i, target)      write the bearing to the target (from the slot centroid) into every slot row's facing
--   AWA.watch(name, i, target, secs)  ammo and per-engine heading/bearing every 5 s into AWA.rows[name]
local mr = _G.memreader_plus
local AWA = _G.AWA or {}
_G.AWA = AWA
AWA.log, AWA.rows = {}, {}

local function note(s) AWA.log[#AWA.log + 1] = string.format('%d %s', bm:time_elapsed_ms(), s) end
local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end
local function unit(i) return bm:get_player_army():units():item(i) end
local function at(hl) return mr.add(mr.add(mr.base, hl[1] * 0x10000), hl[2]) end
local WALL_VT = mr.tostring(at({0x391, 0x1218}))
local function bearing(x0, z0, x1, z1) return math.deg(math.atan2(x1 - x0, z1 - z0)) % 360 end

function AWA.ctl(i)
	local p = obj_of(unit(i))
	if mr.read_int32(p, 0x3310) ~= 1 then return nil, 'controllers ' .. mr.read_int32(p, 0x3310) end
	local c = mr.read_pointer(p, 0x3300)
	if mr.tostring(mr.read_pointer(c, 0)) ~= WALL_VT then return nil, 'controller vtable ' .. mr.tostring(mr.read_pointer(c, 0)) end
	return c
end

function AWA.zone_of(i)
	local c, why = AWA.ctl(i)
	if not c then return nil, why end
	local n, d = mr.read_int32(c, 0x154), mr.read_pointer(c, 0x158)
	local first = mr.read_pointer(d, 0)
	return {zone = mr.read_pointer(c, 0x98), surface = mr.read_pointer(first, 0x30), x = mr.read_float(first, 0x20), z = mr.read_float(first, 0x28), n = n,
		text = string.format('zone %s surface %s slots %d first (%.1f,%.1f,%.1f)', mr.tostring(mr.read_pointer(c, 0x98)), mr.tostring(mr.read_pointer(first, 0x30)), n, mr.read_float(first, 0x20), mr.read_float(first, 0x24), mr.read_float(first, 0x28))}
end

-- the mover's queue_wall, for a unit index and a zone record
function AWA.wall_order(i, t)
	local e = obj_of(unit(i))
	local battle = mr.read_pointer(at({0x448, 0x0da0}), 0)
	local context = mr.read_pointer(battle, 0x468)
	assert(mr.read_uint8(context, 0x3b0) == 0 and mr.read_uint8(context, 0x3b1) == 0, 'battle queue is gated')
	local queue = mr.read_pointer(context, 0x644e8)
	local selection, command, point = mr.alloc(0x80), mr.alloc(0xb0), mr.alloc(8)
	mr.write(point, 0, t.x); mr.write(point, 4, t.z)
	mr.call(at({0x2f2, 0xefc8}), 'pointer(pointer)', selection)
	mr.call(at({0x2f3, 0x7be4}), 'pointer(pointer,pointer,uint8)', selection, e, 0)
	mr.call(at({0x2ea, 0x9754}), 'pointer(pointer,pointer,pointer,pointer,pointer,uint8,uint8)', command, selection, t.zone, point, t.surface, 0, 0)
	local result = mr.call(at({0x2df, 0x5a94}), 'uint8(pointer,pointer)', queue, command)
	mr.call(at({0x1bc, 0xd8ac}), 'pointer(pointer)', mr.add(command, 8))
	mr.call(at({0x1bc, 0xd8ac}), 'pointer(pointer)', selection)
	note(string.format('wall order u%d at (%.0f,%.0f): %s', i, t.x, t.z, mr.tostring(result)))
	return mr.tostring(result)
end

function AWA.slots(i)
	local c, why = AWA.ctl(i)
	if not c then return {why} end
	local n, d, out = mr.read_int32(c, 0x154), mr.read_pointer(c, 0x158), {}
	for k = 0, n - 1 do
		local s = mr.read_pointer(d, k * 8)
		local row, body = mr.read_pointer(s, 0x18), mr.read_pointer(s, 0x40)
		local rx, rz = mr.read_float(row, 0x28), mr.read_float(row, 0x2c)
		local bh = mr.is_null(body) and -1 or mr.read_uint16(body, 0xb0) * 360 / 65536
		out[#out + 1] = string.format('slot %d (%.1f,%.1f,%.1f) row %s facing %.0f body %s heading %.0f', k, mr.read_float(s, 0x20), mr.read_float(s, 0x24), mr.read_float(s, 0x28), mr.tostring(row), bearing(0, 0, rx, rz), mr.tostring(body), bh)
	end
	return out
end

-- write the bearing from the slot centroid to the target into every (distinct) slot row's facing vector
function AWA.face(i, target)
	local c, why = AWA.ctl(i)
	if not c then return why end
	local n, d = mr.read_int32(c, 0x154), mr.read_pointer(c, 0x158)
	local cx, cz = 0, 0
	for k = 0, n - 1 do local s = mr.read_pointer(d, k * 8); cx, cz = cx + mr.read_float(s, 0x20) / n, cz + mr.read_float(s, 0x28) / n end
	local tp = target:position()
	local br = bearing(cx, cz, tp:get_x(), tp:get_z())
	local vx, vz = math.sin(math.rad(br)), math.cos(math.rad(br))
	local rows, written = {}, 0
	for k = 0, n - 1 do
		local row = mr.tostring(mr.read_pointer(mr.read_pointer(d, k * 8), 0x18))
		if not rows[row] then rows[row] = true; mr.write(mr.read_pointer(mr.read_pointer(d, k * 8), 0x18), 0x28, vx); mr.write(mr.read_pointer(mr.read_pointer(d, k * 8), 0x18), 0x2c, vz); written = written + 1 end
	end
	return string.format('u%d faced %.0f (%d rows)', i, br, written)
end

function AWA.watch(name, i, target, secs)
	AWA.rows[name] = {}
	local t0 = bm:time_elapsed_ms()
	bm:remove_process('awa_' .. name)
	bm:repeat_callback(function()
		local now = bm:time_elapsed_ms()
		local p = obj_of(unit(i))
		local d, n = mr.read_pointer(p, 0x188), mr.read_int32(p, 0x184)
		local tp, hs = target:position(), {}
		for k = 0, n - 1 do
			local b = mr.read_pointer(d, k * 8)
			local x, z = mr.read_float(b, 0x910), mr.read_float(b, 0x918)
			hs[#hs + 1] = string.format('%.0f/%.0f', mr.read_uint16(b, 0xb0) * 360 / 65536, bearing(x, z, tp:get_x(), tp:get_z()))
		end
		AWA.rows[name][#AWA.rows[name] + 1] = string.format('%d ammo %d heading/bearing %s', now - t0, unit(i):ammo_left(), table.concat(hs, ' '))
		if now - t0 >= secs * 1000 then bm:remove_process('awa_' .. name) end
	end, 5000, 'awa_' .. name)
	return 'watching ' .. name
end

return 'arc probe loaded'
