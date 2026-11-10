-- SPIKE: the open-item battle (2026-11-01) - one Chaos Dwarf battery through climb, firing from the wall, a
-- mover-off descent under PK recording, and the abandonment hooks armed throughout. Loaded over the wh3 bridge
-- after setup_deployed.lua, artwalls_probe.lua (AW), artwalls_park_probe.lua (PK) and artwalls_hooks.lua (AWH).
-- AWI.arm()                  caves on the two abandonment entry points, polled; AWH.report('aband') reads them
-- AWI.trace(i)               1 s trace of unit i's engines (x,y,z,wall) and crew up, into AWI.rows
-- AWI.sample(i)              one sample now
-- AWI.fire(i, at, secs)      an enemy unit put at `at`, fire at will on unit i for `secs`, ammo read every second
-- AWI.descend(i, ground)     the mover's two processes removed, PK recording, halt + ground order
-- AWI.write(path, note)      trace + ammo + hook report
local mr = _G.memreader_plus
local AWI = _G.AWI or {}
_G.AWI = AWI

local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end
local function unit(i) return bm:get_player_army():units():item(i) end

function AWI.sample(i)
	local p = obj_of(unit(i))
	local men, total, up = mr.read_pointer(p, 0xa8), mr.read_int32(p, 0xa4), 0
	for k = 0, total - 1 do
		if not mr.is_null(mr.read_pointer(mr.read_pointer(men, k * 8), 0x920)) then up = up + 1 end
	end
	local d, n, eup, line = mr.read_pointer(p, 0x188), mr.read_int32(p, 0x184), 0, ''
	for k = 0, n - 1 do
		local b = mr.read_pointer(d, k * 8)
		local w = not mr.is_null(mr.read_pointer(b, 0x920))
		if w then eup = eup + 1 end
		line = line .. string.format(' %.0f,%.0f,%.0f,w%d', mr.read_float(b, 0x910), mr.read_float(b, 0x914), mr.read_float(b, 0x918), w and 1 or 0)
	end
	return {engines = n, engines_up = eup, crew = total, crew_up = up, line = line, ammo = unit(i):ammo_left()}
end

function AWI.arm()
	local ents = AWH.entities()
	local r1 = AWH.hook('aband', {0x306, 0x5744}, true)
	local r2 = AWH.hook('aband2', {0x306, 0x5a94}, true)
	local function who(rcx, rdx, r8)
		return string.format('rcx=%s(%s) rdx=%s(%s) r8=%s', mr.tostring(rcx), ents[mr.tostring(rcx)] or '?', mr.tostring(rdx), ents[mr.tostring(rdx)] or '?', mr.tostring(r8))
	end
	AWH.poll('aband', who)
	AWH.poll('aband2', who)
	return r1 .. ' / ' .. r2
end

function AWI.trace(i)
	AWI.rows = AWI.rows or {}
	bm:remove_process('awi')
	bm:repeat_callback(function()
		local ok, e = pcall(function()
			local s = AWI.sample(i)
			AWI.rows[#AWI.rows + 1] = string.format('%d u%d cw%d/%d eng%d/%d ammo%d%s', bm:time_elapsed_ms(), i, s.crew_up, s.crew, s.engines_up, s.engines, s.ammo, s.line)
		end)
		if not ok then AWI.err = tostring(e) end
	end, 1000, 'awi')
end

function AWI.fire(i, at, secs)
	AWI.ammo = {}
	local c = AWT.enemy[1]
	c:teleport_to_location(battle_vector:new(at.x, 0, at.z), 0, 50)
	local u = AWT.uc[i]
	u:take_control(); u:fire_at_will(true); u:release_control()
	local t0 = bm:time_elapsed_ms()
	bm:remove_process('awi_fire')
	bm:repeat_callback(function()
		local now = bm:time_elapsed_ms()
		AWI.ammo[#AWI.ammo + 1] = string.format('%d ammo %d', now, unit(i):ammo_left())
		if now - t0 >= secs * 1000 then
			u:take_control(); u:fire_at_will(false); u:release_control()
			c:teleport_to_location(battle_vector:new(-40, 0, -520), 0, 100)
			bm:remove_process('awi_fire')
		end
	end, 1000, 'awi_fire')
	return 'firing ' .. secs .. ' s from ammo ' .. unit(i):ammo_left()
end

function AWI.descend(i, ground)
	bm:remove_process('derpy_artillery_walls')
	bm:remove_process('derpy_artillery_walls_exit')
	local r = PK.start(i)
	local u = AWT.uc[i]
	u:take_control(); u:halt()
	u:goto_location_angle_width(battle_vector:new(ground.x, 0, ground.z), 180, 50)
	u:release_control()
	return 'mover off, ' .. r
end

-- Another map: no wall coordinates known, so the defenders' own men say where the walls are. Every enemy man
-- standing on a surface (+0x920 set), grouped by surface id, BEFORE setup_deployed.lua teleports them away.
function AWI.find_walls()
	local out, seen = {}, {}
	for a = 1, bm:alliances():count() do
		if a ~= bm:get_player_alliance_num() then
			local armies = bm:alliances():item(a):armies()
			for j = 1, armies:count() do
				local us = armies:item(j):units()
				for i = 1, us:count() do
					local p = obj_of(us:item(i))
					local men, total = mr.read_pointer(p, 0xa8), mr.read_int32(p, 0xa4)
					for k = 0, total - 1 do
						local m = mr.read_pointer(men, k * 8)
						local surf = mr.read_pointer(m, 0x920)
						if not mr.is_null(surf) then
							local id = mr.read_int32(surf, 0x28)
							if not seen[id] then
								seen[id] = true
								out[#out + 1] = string.format('surface %d: %s man %d at (%.1f, %.1f, %.1f)', id, us:item(i):type(), k, mr.read_float(m, 0x910), mr.read_float(m, 0x914), mr.read_float(m, 0x918))
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- AW.capture for a man of any unit object: fills AW.POS the way AW.capture does
function AWI.capture_unit(u, want_id)
	local o = obj_of(u)
	local n, data = mr.read_int32(o, 0xa4), mr.read_pointer(o, 0xa8)
	for k = 0, n - 1 do
		local m = mr.read_pointer(data, k * 8)
		local surf = mr.read_pointer(m, 0x920)
		if not mr.is_null(surf) and (not want_id or mr.read_int32(surf, 0x28) == want_id) then
			AW.POS = AW.POS or mr.alloc(0x20)
			for off = 0, 8, 4 do mr.write(AW.POS, off, mr.read_float(m, 0x910 + off)) end
			mr.write(AW.POS, 0xc, mr.uint32(0))
			mr.write(AW.POS, 0x10, surf)
			mr.write(AW.POS, 0x18, mr.read_pointer(m, 0x910 + 0x18))
			return string.format('man %d at (%.1f, %.1f, %.1f) surface id %d', k, mr.read_float(m, 0x910), mr.read_float(m, 0x914), mr.read_float(m, 0x918), mr.read_int32(surf, 0x28))
		end
	end
	return nil
end

function AWI.write(path, note)
	local f = assert(io.open(path, 'w'))
	f:write(note or '', '\n--- trace: t unit crew_up/crew engines_up/engines ammo then per engine x,y,z,wall\n')
	for _, l in ipairs(AWI.rows or {}) do f:write(l, '\n') end
	f:write('--- ammo\n')
	for _, l in ipairs(AWI.ammo or {}) do f:write(l, '\n') end
	for _, n in ipairs({'aband', 'aband2'}) do
		if AWH.g and AWH.g[n] then f:write('--- hook ', n, '\n', AWH.report(n), '\n') end
	end
	f:write('--- err ', tostring(AWI.err), '\n')
	f:close()
	return #(AWI.rows or {})
end

return 'items probe loaded'
