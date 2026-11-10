-- SPIKE: why does one engine of a battery park short of a stair on a wall-height MOVE (build 6acec6f4)?
-- Loaded over the wh3 bridge in a battle after setup_deployed.lua. Records, every 500 ms, each engine body's
-- command vtable, path state, order kind, wait tick, goal and goal surface, next to its position, so a parked
-- engine can be compared with the one beside it that climbed.
-- PK.start(unit_index)   begin recording unit i's engines (default 3)
-- PK.last()              one line per engine, the latest sample
-- PK.diff(k, t0, t1)     engine k's fields at the two sample times, side by side
-- PK.write(path, note)   dump every sample as text
local mr = _G.memreader_plus
assert(mr, "memreader Plus is not loaded")
local PK = _G.PK or {}
_G.PK = PK

local F = { -- offset, kind, name (kinds: p pointer, i int32, u8, u16, f float)
	{0x330, 'p', 'cmd'}, {0x340, 'u8', 'cmd_done'}, {0x710, 'i', 'path'}, {0x324, 'i', 'kind'}, {0x884, 'i', 'wait'},
	{0x108, 'i', 'flags'}, {0x8b0, 'i', 'f8b0'}, {0x7f8, 'f', 'gx'}, {0x7fc, 'f', 'gy'}, {0x800, 'f', 'gz'}, {0x808, 'p', 'gsurf'},
	{0x368, 'f', 'wx'}, {0x370, 'f', 'wz'}, {0x378, 'p', 'wsurf'}, {0x3c0, 'p', 'w3c0'}, {0x490 + 0x130, 'u8', 'act_has'},
	{0x5c8 + 0x130, 'u8', 'q_has'}, {0x88a, 'u8', 'f88a'}, {0xb20, 'p', 'b20'}, {0x968, 'p', 'slot968'}, {0x128, 'p', 'f128'},
}
local function read(b, f)
	local off, k = f[1], f[2]
	if k == 'p' then return mr.tostring(mr.read_pointer(b, off)) end
	if k == 'i' then return mr.read_int32(b, off) end
	if k == 'u8' then return mr.read_uint8(b, off) end
	if k == 'u16' then return mr.read_uint16(b, off) end
	local v = mr.read_float(b, off); return math.floor(v * 10) / 10
end

local function obj_of(unit) return mr.read_pointer(mr.ud_topointer(unit), 8) end

function PK.start(i)
	local u = bm:get_player_army():units():item(i or 3)
	local o = obj_of(u)
	PK.unit, PK.obj, PK.rows, PK.err = u, o, {}, nil
	local b0 = mr.read_pointer(mr.read_pointer(o, 0x188), 0)
	PK.battle = mr.read_pointer(mr.read_pointer(b0, 0x58), 0x440)
	bm:remove_process('pk')
	bm:repeat_callback(function()
		local ok, e = pcall(function()
			local r = {t = bm:time_elapsed_ms(), tick = mr.read_int32(PK.battle, 0x98), e = {}}
			local d = mr.read_pointer(o, 0x188)
			for k = 0, mr.read_int32(o, 0x184) - 1 do
				local b = mr.read_pointer(d, k * 8)
				local s = {x = read(b, {0x910, 'f'}), y = read(b, {0x914, 'f'}), z = read(b, {0x918, 'f'}),
					w = mr.is_null(mr.read_pointer(b, 0x920)) and 0 or 1, h = mr.read_uint16(b, 0xb0)}
				for _, f in ipairs(F) do s[f[3]] = read(b, f) end
				r.e[k + 1] = s
			end
			PK.rows[#PK.rows + 1] = r
		end)
		if not ok then PK.err = tostring(e) end
	end, 500, 'pk')
	return string.format('recording %d engines, battle %s tick %d', mr.read_int32(o, 0x184), mr.tostring(PK.battle), mr.read_int32(PK.battle, 0x98))
end

local ORDER = {'x', 'y', 'z', 'w', 'h', 'cmd', 'cmd_done', 'path', 'kind', 'wait', 'flags', 'f8b0', 'gx', 'gy', 'gz', 'gsurf',
	'wx', 'wz', 'wsurf', 'w3c0', 'act_has', 'q_has', 'f88a', 'b20', 'slot968', 'f128'}
local function line(r, k)
	local s = r.e[k]
	local out = {}
	for _, n in ipairs(ORDER) do
		local v = s[n]
		if type(v) == 'string' then v = v:gsub('^0+', '') end
		out[#out + 1] = n .. '=' .. tostring(v)
	end
	return string.format('t%d tick%d e%d ', r.t, r.tick, k) .. table.concat(out, ' ')
end

function PK.last()
	local r = PK.rows[#PK.rows]
	local out = {n = #PK.rows, err = PK.err}
	for k = 1, #r.e do out[k] = line(r, k) end
	return out
end

function PK.diff(k, t0, t1)
	local a, b
	for _, r in ipairs(PK.rows) do
		if not a and r.t >= t0 then a = r end
		if not b and r.t >= t1 then b = r end
	end
	return {line(a, k), line(b, k)}
end

function PK.write(path, note)
	local f = assert(io.open(path, 'w'))
	f:write(note or '', '\n')
	for _, r in ipairs(PK.rows) do
		for k = 1, #r.e do f:write(line(r, k), '\n') end
	end
	f:close()
	return #PK.rows
end

return 'park probe loaded'
