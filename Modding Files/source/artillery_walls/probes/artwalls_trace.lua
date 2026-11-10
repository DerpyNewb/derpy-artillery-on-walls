-- SPIKE: how an infantry man is put on the wall. Samples man k of player unit i every 200 ms and keeps the
-- dwords of the man (0x1000) and of his unit (0x4000) from the tick before and the tick after his surface
-- (+0x920) changes or he moves more than 2.5 m in one tick.
-- AWT.start(i, k)  AWT.stop()  AWT.trail()  AWT.diff(n, which)
local mr = _G.memreader_plus
local AWT = _G.AWT or {}
_G.AWT = AWT

local MAN_N, UNIT_N = 0x1000 / 4, 0x4000 / 4

local function dump(p, n)
	local t = {}
	for j = 0, n - 1 do t[j] = mr.read_int32(p, j * 4) end
	return t
end

function AWT.start(i, k)
	bm:remove_process("awt")
	local u = bm:get_player_army():units():item(i)
	local o = mr.read_pointer(mr.ud_topointer(u), 8)
	local m = mr.read_pointer(mr.read_pointer(o, 0xa8), (k or 0) * 8)
	AWT.unit, AWT.man, AWT.events, AWT.log = o, m, {}, {}
	local prev = { man = dump(m, MAN_N), unit = dump(o, UNIT_N), x = mr.read_float(m, 0x910), y = mr.read_float(m, 0x914),
		z = mr.read_float(m, 0x918), s = mr.tostring(mr.read_pointer(m, 0x920)), t = bm:time_elapsed_ms() }
	bm:repeat_callback(function()
		local ok, err = pcall(function()
			local cur = { x = mr.read_float(m, 0x910), y = mr.read_float(m, 0x914), z = mr.read_float(m, 0x918),
				s = mr.tostring(mr.read_pointer(m, 0x920)), t = bm:time_elapsed_ms() }
			cur.man, cur.unit = dump(m, MAN_N), dump(o, UNIT_N)
			local d2 = (cur.x - prev.x) ^ 2 + (cur.y - prev.y) ^ 2 + (cur.z - prev.z) ^ 2
			AWT.log[#AWT.log + 1] = string.format("%d (%.1f,%.1f,%.1f) %s p30=%s p220=%s 110=%d 218=%d 240=%d", cur.t, cur.x, cur.y, cur.z,
				cur.s:sub(-6), mr.tostring(mr.read_pointer(m, 0x30)):sub(-9), mr.tostring(mr.read_pointer(m, 0x220)):sub(-9),
				mr.read_int32(m, 0x110), mr.read_int32(m, 0x218), mr.read_int32(m, 0x240))
			local pp = mr.read_pointer(m, 0x220)
			if not mr.is_null(pp) and not AWT.pipe then AWT.pipe = pp end
			if (cur.s ~= prev.s or d2 > 2.5 * 2.5) and #AWT.events < 6 then
				AWT.events[#AWT.events + 1] = { before = prev, after = cur, d = math.sqrt(d2) }
			end
			prev = cur
		end)
		if not ok then AWT.err = tostring(err) bm:remove_process("awt") end
	end, 200, "awt")
	return "tracing"
end

function AWT.stop() bm:remove_process("awt") return #AWT.log end

function AWT.trail(from, to)
	local out = {}
	for j = from or 1, math.min(to or #AWT.log, #AWT.log) do out[#out + 1] = AWT.log[j] end
	return table.concat(out, "\n")
end

-- the offsets whose dword changed across event n, as "+off before->after"
function AWT.diff(n, which, limit)
	local e = AWT.events[n]
	local a, b = e.before[which or "man"], e.after[which or "man"]
	local out = { string.format("event %d t %d->%d d=%.1f surf %s->%s", n, e.before.t, e.after.t, e.d, e.before.s, e.after.s) }
	for j = 0, #a do
		if a[j] ~= b[j] then
			out[#out + 1] = string.format("+%x %d->%d", j * 4, a[j], b[j])
			if #out > (limit or 200) then break end
		end
	end
	return table.concat(out, "\n")
end

return "artwalls trace loaded"
