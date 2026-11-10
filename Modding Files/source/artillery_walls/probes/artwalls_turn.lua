-- Run 35 on (2026-11-10): how far round a docked gun turns and fires. Load after artwalls_static.lua,
-- artwalls_engines.lua, artwalls_dock.lua and artwalls_bump.lua, once both batteries are docked and AWE.start(name)
-- counts shots.
--   AWT.place(label, x, z)      move the held enemy there and start a step (the shot counts are taken from here)
--   AWT.read()                  the step so far: enemy centroid, then per engine x, heading, bearing to the enemy,
--                               shots in the step and +0xce0
--   AWT.sweep(gx, gz, offs, ms) the enemy 250 m out round the point gx, gz at each angle off the wall's 180 facing
--                               (positive: west), one step every ms; rows into AWT.log, AWT.done when finished
--   AWT.sample(ms)              every ms into AWT.rows: per battery its order (+0x2f88) and wall controller (+0x3310),
--                               per engine x, z, heading, +0xce0 and +0x5c0 (an action assigned)
--   AWT.save(name)              AWT.log and AWT.rows into Backup/artillery_walls/20261109/<name>.txt
local mr = _G.memreader_plus
local AWT = _G.AWT or {}
_G.AWT = AWT
local DIR = 'G:/Modding for resources/Modding Files/Backup/artillery_walls/20261109/'
AWT.name = AWT.name or 'run'
AWT.log, AWT.rows = AWT.log or {}, AWT.rows or {}

local function run() return AWE.runs[AWT.name] end
local function snap() local s = {}; for k, v in pairs(run().shots) do s[k] = v end; return s end
local function uptr(i) return mr.read_pointer(mr.ud_topointer(bm:get_player_army():units():item(i)), 8) end

function AWT.place(label, x, z)
	AWS.place(x, z, 20)
	AWT.cur = {label = label, t = bm:time_elapsed_ms(), s = snap()}
	return label
end

function AWT.read()
	local c = AWT.cur
	local ex, ez, n = 0, 0, 0
	local us = bm:get_non_player_alliance():armies():item(1):units()
	for i = 1, us:count() do local p = us:item(i):position(); ex, ez, n = ex + p:get_x(), ez + p:get_z(), n + 1 end
	ex, ez = ex / n, ez / n
	local rows = {}
	for _, i in ipairs(run().units) do for _, b in ipairs(AWE.engines(i)) do
		local key = i .. '@' .. mr.tostring(b)
		local x, z = mr.read_float(b, 0x910), mr.read_float(b, 0x918)
		rows[#rows + 1] = string.format('u%d x%.0f h%.0f (bearing %.0f) shots %d ce0 %x', i, x, mr.read_uint16(b, 0xb0) * 360 / 65536,
			math.deg(math.atan2(ex - x, ez - z)) % 360, (run().shots[key] or 0) - (c.s[key] or 0), mr.read_int32(b, 0xce0))
	end end
	return string.format('%s: enemy at %.0f,%.0f, %.0f s | %s', c.label, ex, ez, (bm:time_elapsed_ms() - c.t) / 1000, table.concat(rows, ' | '))
end

function AWT.sweep(gx, gz, offs, ms)
	local k = 0
	AWT.done = false
	local function step()
		if k > 0 then AWT.log[#AWT.log + 1] = AWT.read() end
		k = k + 1
		local off = offs[k]
		if not off then bm:remove_process('awt_sweep'); AWT.done = true; return end
		local r = math.rad(off)
		AWT.place('off ' .. off, gx - 250 * math.sin(r), gz - 250 * math.cos(r))
	end
	bm:remove_process('awt_sweep')
	step()
	bm:repeat_callback(function() pcall(step) end, ms, 'awt_sweep')
	return AWT.cur.label
end

function AWT.row()
	local parts = {math.floor(bm:time_elapsed_ms() / 1000)}
	for _, i in ipairs(run().units) do
		local e = {}
		for _, b in ipairs(AWE.engines(i)) do
			e[#e + 1] = string.format('%.1f,%.1f h%.0f c%x a%d', mr.read_float(b, 0x910), mr.read_float(b, 0x918),
				mr.read_uint16(b, 0xb0) * 360 / 65536, mr.read_int32(b, 0xce0), mr.read_uint8(b, 0x5c0))
		end
		parts[#parts + 1] = string.format('u%d ord%d ctl%d: %s', i, mr.read_int32(uptr(i), 0x2f88), mr.read_int32(uptr(i), 0x3310), table.concat(e, ' '))
	end
	return table.concat(parts, ' | ')
end

function AWT.sample(ms)
	bm:remove_process('awt_sample')
	bm:repeat_callback(function() pcall(function() AWT.rows[#AWT.rows + 1] = AWT.row() end) end, ms, 'awt_sample')
	return AWT.row()
end

function AWT.save(name)
	local f = io.open(DIR .. name .. '.txt', 'w')
	f:write(table.concat(AWT.log, '\n') .. '\n-- samples\n' .. table.concat(AWT.rows, '\n') .. '\n')
	f:close()
	return #AWT.log + #AWT.rows
end

return 'artwalls turn probe loaded'
