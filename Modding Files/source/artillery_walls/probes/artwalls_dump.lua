-- SPIKE (2026-11-09): body snapshots for a moving-vs-stalled diff. Needs artwalls_engines.lua (AWE) loaded first.
--   AWD.snap(tag, units)  appends one block per engine of each player unit index in units (default {4}) to
--                         AWD.FILE: a header line, then the body's first 0xe00 bytes and its command (+0x330 -> 0x100)
--                         as u32 hex words, eight per line. Diffed offline by tools/artwalls_diff.py.
local mr = _G.memreader_plus
local AWD = _G.AWD or {}
_G.AWD = AWD
AWD.FILE = 'G:/Modding for resources/Modding Files/Backup/artillery_walls/20261109/body_dumps.txt'

local function words(p, n)
	local out = {}
	for off = 0, n - 4, 4 do out[#out + 1] = string.format('%08x', mr.read_int32(p, off) % 4294967296) end
	return out
end

local function manned(b)
	local n, sl, m = mr.read_int32(b, 0xc1c), mr.read_pointer(b, 0xc20), 0
	for j = 0, n - 1 do if mr.read_uint8(mr.read_pointer(sl, j * 8), 0x81) == 1 then m = m + 1 end end
	return m, n
end

function AWD.snap(tag, units)
	local f = assert(io.open(AWD.FILE, 'a'))
	local rows = {}
	for _, i in ipairs(units or {4}) do
		for k, b in ipairs(AWE.engines(i)) do
			local m, n = manned(b)
			local head = string.format('# %s t=%d u%d e%d body=%s x=%.2f y=%.2f z=%.2f h=%d manned=%d/%d wall=%d', tag,
				bm:time_elapsed_ms(), i, k, mr.tostring(b), mr.read_float(b, 0x910), mr.read_float(b, 0x914),
				mr.read_float(b, 0x918), mr.read_uint16(b, 0xb0), m, n, mr.is_null(mr.read_pointer(b, 0x920)) and 0 or 1)
			rows[#rows + 1] = head
			f:write(head, '\n')
			local w = words(b, 0xe00)
			for off = 1, #w, 8 do f:write(string.format('B %04x ', (off - 1) * 4), table.concat(w, ' ', off, math.min(off + 7, #w)), '\n') end
			local c = mr.read_pointer(b, 0x330)
			if not mr.is_null(c) then
				local cw = words(c, 0x100)
				for off = 1, #cw, 8 do f:write(string.format('C %04x ', (off - 1) * 4), table.concat(cw, ' ', off, math.min(off + 7, #cw)), '\n') end
			end
		end
	end
	f:close()
	return table.concat(rows, '\n')
end

return 'artwalls dump loaded'
