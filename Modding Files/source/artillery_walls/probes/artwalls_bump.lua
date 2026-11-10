-- Runs 18-21: one race's two artillery units (player units 3 and 4) on the Altdorf z -339 wall. Load after
-- artwalls_static.lua, artwalls_engines.lua and artwalls_dock.lua, once the battle is Deployed.
--   AWB.begin()        1 s sampler: every engine's radius against its battle_entities radius (half on a wall, full
--                      off it), its deploy state, and any crew task of a standing engine walking past the parapet face
--   AWB.dock(i, x)     CA's own wall-zone order (occupy_zone, as the right-click on a wall) for unit i at x
--   AWB.crew()         every crewman's radius against his own battle_entities radius
--   AWB.watch(i)       from now on, how far each engine of unit i moves from where it stands (200 ms)
--   AWB.status()       one line per engine, the radius verdict, the parapet hits and the drift
--   AWB.save(name)     the sampler rows into Backup/artillery_walls/20261109/<name>_*.txt
local mr = _G.memreader_plus
local AWB = _G.AWB or {}
_G.AWB = AWB
local FACE = -339.4 -- z of the parapet face on this wall
local DIR = 'G:/Modding for resources/Modding Files/Backup/artillery_walls/20261109/'

local function full(b) return mr.read_float(mr.read_pointer(b, 0x2d8), 0x5c) end
local function on_wall(b) return not mr.is_null(mr.read_pointer(b, 0x920)) end

function AWB.begin()
	AWB.rows, AWB.deep, AWB.bad, AWB.seen = {}, {}, {}, {}
	bm:remove_process('awb_sample')
	bm:repeat_callback(function() pcall(function()
		local t = math.floor(bm:time_elapsed_ms() / 1000)
		for _, i in ipairs(_G.AW_UNITS or {3, 4}) do for k, b in ipairs(AWE.engines(i)) do
			local w, a0, r = on_wall(b), mr.read_float(b, 0xa0), full(b)
			local row = string.format('%d u%de%d a0 %.2f full %.2f wall %s x %.1f y %.1f z %.1f ce0 %x path %d', t, i, k, a0, r,
				tostring(w), mr.read_float(b, 0x910), mr.read_float(b, 0x914), mr.read_float(b, 0x918), mr.read_int32(b, 0xce0),
				mr.read_int32(b, 0x710))
			AWB.rows[#AWB.rows + 1] = row
			local want = w and r * 0.5 or r
			if math.abs(a0 - want) > 0.01 then AWB.bad[#AWB.bad + 1] = row end
			AWB.seen[string.format('u%d %s %.2f', i, w and 'wall' or 'ground', a0)] = true
			if w and mr.read_int32(b, 0x710) ~= 4 then
				local tl = mr.read_pointer(b, 0xc10)
				for j = 0, mr.read_int32(b, 0xc0c) - 1 do
					local tk = mr.read_pointer(tl, j * 8)
					if mr.read_int32(tk, 0x18) == 1 and mr.read_float(tk, 0x50) < FACE then
						AWB.deep[#AWB.deep + 1] = string.format('%d u%de%d task %d off (%.2f,%.2f) at z %.2f', t, i, k, j,
							mr.read_float(tk, 0x38), mr.read_float(tk, 0x3c), mr.read_float(tk, 0x50))
					end
				end
			end
		end end
	end) end, 1000, 'awb_sample')
	return 'sampling'
end

function AWB.dock(i, x) return AWE.zone(i, x, 106.6, -339) end

function AWB.crew()
	local out = {}
	for _, i in ipairs(_G.AW_UNITS or {3, 4}) do
		local counts, n = {}, 0
		for _, b in ipairs(AWE.engines(i)) do
			local slots = mr.read_pointer(b, 0xc20)
			for j = 0, mr.read_int32(b, 0xc1c) - 1 do
				local m = mr.read_pointer(mr.read_pointer(slots, j * 8), 0x10)
				if not mr.is_null(m) then
					n = n + 1
					local key = string.format('%.2f of %.2f %s', mr.read_float(m, 0xa0), full(m), on_wall(m) and 'wall' or 'ground')
					counts[key] = (counts[key] or 0) + 1
				end
			end
		end
		local s = {}
		for key, c in pairs(counts) do s[#s + 1] = key .. ' x' .. c end
		table.sort(s)
		out[#out + 1] = string.format('u%d crew %d: %s', i, n, table.concat(s, ', '))
	end
	return out
end

function AWB.watch(i)
	AWB.start, AWB.maxd, AWB.from = {}, {}, math.floor(bm:time_elapsed_ms() / 1000)
	for k, b in ipairs(AWE.engines(i)) do AWB.start[k] = {mr.read_float(b, 0x910), mr.read_float(b, 0x918)}; AWB.maxd[k] = 0 end
	bm:remove_process('awb_drift')
	bm:repeat_callback(function() pcall(function()
		for k, b in ipairs(AWE.engines(i)) do
			local s = AWB.start[k]
			local d = math.sqrt((mr.read_float(b, 0x910) - s[1])^2 + (mr.read_float(b, 0x918) - s[2])^2)
			if d > AWB.maxd[k] then AWB.maxd[k] = d end
		end
	end) end, 200, 'awb_drift')
	return #AWB.start
end

function AWB.status()
	local out = {t = math.floor(bm:time_elapsed_ms() / 1000), mismatches = #AWB.bad, deep = #AWB.deep}
	local seen = {}
	for key in pairs(AWB.seen) do seen[#seen + 1] = key end
	table.sort(seen)
	out.radii = table.concat(seen, ' | ')
	local n = #AWB.rows
	out.now = {}
	for k = math.max(1, n - 7), n do out.now[#out.now + 1] = AWB.rows[k] end
	for k = 1, math.min(3, #AWB.bad) do out['bad' .. k] = AWB.bad[k] end
	for k = math.max(1, #AWB.deep - 2), #AWB.deep do out['deep' .. k] = AWB.deep[k] end
	if AWB.maxd then
		local d = {}
		for k, v in ipairs(AWB.maxd) do d[k] = string.format('%.2f', v) end
		out.drift = table.concat(d, ' ') .. ' m since ' .. AWB.from
	end
	return out
end

function AWB.save(name)
	local f = io.open(DIR .. name .. '_radius.txt', 'w')
	for _, l in ipairs(AWB.rows) do f:write(l, '\n') end
	f:write('-- deep\n')
	for _, l in ipairs(AWB.deep) do f:write(l, '\n') end
	f:close()
	f = io.open(DIR .. name .. '_cmd.txt', 'w')
	for _, l in ipairs(AWX.cl or {}) do f:write(tostring(l), '\n') end
	f:close()
	return #AWB.rows
end

return 'artwalls bump probe loaded'
