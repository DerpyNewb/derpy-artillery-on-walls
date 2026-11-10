-- SPIKE: trace caves for the artillery-on-walls research (build 6acec6f4). Loaded over the wh3 bridge in a battle.
-- AWH.hook(name, {hi, lo})   a cave at a function entry that records rcx, rdx, r8, r9, 0x40 bytes at [r8] and 0x400
--                            bytes of stack into a buffer; the site's first instructions must not be rip-relative.
--                            [r8] is read unconditionally: hook only functions whose r8 is always a valid pointer.
-- AWH.poll(name, who)        start a 100 ms poller that groups hits by call-stack signature; who(rcx, rdx, r8) names
--                            the hit or returns nil to drop it.
-- AWH.report(name)           the groups, most recent block bytes for each.
-- Caves cannot be removed for the session; the owner is "aw_trace", so a later battle reuses the same buffers.
local mr = _G.memreader_plus
local base = mr.base
local function at(hl) return mr.add(mr.add(base, hl[1] * 0x10000), hl[2]) end

local AWH = _G.AWH or { b = {} }
_G.AWH = AWH

local BODY = {0xFF, 0x07, 0x48, 0x89, 0x4F, 0x08, 0x48, 0x89, 0x57, 0x10, 0x4C, 0x89, 0x47, 0x18, 0x4C, 0x89, 0x4F, 0x20,
	0x4C, 0x89, 0xC6, 0x48, 0x83, 0xC7, 0x28, 0xB9, 0x40, 0x00, 0x00, 0x00, 0xF3, 0xA4,
	0x48, 0x8D, 0x74, 0x24, 0x20, 0xB9, 0x00, 0x04, 0x00, 0x00, 0xF3, 0xA4, 0x58, 0x59, 0x5F, 0x5E}

-- the same without the [r8] copy, for a function whose r8 is not a pointer
local SAFE = {0xFF, 0x07, 0x48, 0x89, 0x4F, 0x08, 0x48, 0x89, 0x57, 0x10, 0x4C, 0x89, 0x47, 0x18, 0x4C, 0x89, 0x4F, 0x20,
	0x48, 0x83, 0xC7, 0x68, 0x48, 0x8D, 0x74, 0x24, 0x20, 0xB9, 0x00, 0x04, 0x00, 0x00, 0xF3, 0xA4, 0x58, 0x59, 0x5F, 0x5E}

function AWH.hook(name, hl, safe)
	local site = at(hl)
	local info = mr.hook_info(site)
	if info and info.kind == "cave" then
		AWH.b[name] = mr.read_pointer(info.cave, 6)
		return "reused"
	end
	local buf = mr.game_alloc(0x500)
	mr.write(buf, 0, mr.uint32(0))
	local hex = mr.tostring(buf)
	local b = {0x56, 0x57, 0x51, 0x50, 0x48, 0xBF}
	for i = 0, 7 do b[#b + 1] = tonumber(hex:sub(15 - 2 * i, 16 - 2 * i), 16) end
	for _, x in ipairs(safe and SAFE or BODY) do b[#b + 1] = x end
	local cave, why = mr.patcher("aw_trace"):cave(name, site, string.char(unpack(b)))
	if not cave then return "failed: " .. tostring(why) end
	AWH.b[name] = buf
	return "hooked"
end

-- the same as SAFE, recorded only when [rcx+0x2e8] (the unit of a man or a body) equals the pointer at buffer +0x4f8
local FILTERED = {0x48, 0x8B, 0x81, 0xE8, 0x02, 0x00, 0x00, 0x48, 0x3B, 0x87, 0xF8, 0x04, 0x00, 0x00, 0x75, 0x22, 0xFF, 0x07,
	0x48, 0x89, 0x4F, 0x08, 0x48, 0x89, 0x57, 0x10, 0x4C, 0x89, 0x47, 0x18, 0x4C, 0x89, 0x4F, 0x20, 0x48, 0x8D, 0x74, 0x24, 0x20,
	0x48, 0x83, 0xC7, 0x68, 0xB9, 0x00, 0x04, 0x00, 0x00, 0xF3, 0xA4, 0x58, 0x59, 0x5F, 0x5E}

-- the same, keyed on a behaviour: recorded only when [[rcx+8]+0xa10] (regiment AI -> unit) equals buffer +0x4f8
local BFILTERED = {0x48, 0x8B, 0x41, 0x08, 0x48, 0x85, 0xC0, 0x74, 0x32, 0x48, 0x8B, 0x80, 0x10, 0x0A, 0x00, 0x00, 0x48, 0x3B,
	0x87, 0xF8, 0x04, 0x00, 0x00, 0x75, 0x22, 0xFF, 0x07, 0x48, 0x89, 0x4F, 0x08, 0x48, 0x89, 0x57, 0x10, 0x4C, 0x89, 0x47, 0x18,
	0x4C, 0x89, 0x4F, 0x20, 0x48, 0x8D, 0x74, 0x24, 0x20, 0x48, 0x83, 0xC7, 0x68, 0xB9, 0x00, 0x04, 0x00, 0x00, 0xF3, 0xA4, 0x58,
	0x59, 0x5F, 0x5E}

-- AWH.fhook(name, {hi, lo}, unit[, behaviour]): a trace cave that records only calls whose rcx belongs to unit (a man or
-- a body; with behaviour true, a behaviour whose +8 is the regiment AI object). Re-aimed on reuse.
function AWH.fhook(name, hl, unit, behaviour)
	local site = at(hl)
	local info = mr.hook_info(site)
	local buf
	if info and info.kind == "cave" then
		buf = mr.read_pointer(info.cave, 6)
	else
		buf = mr.game_alloc(0x500)
		mr.write(buf, 0, mr.uint32(0))
		local hex = mr.tostring(buf)
		local b = {0x56, 0x57, 0x51, 0x50, 0x48, 0xBF}
		for i = 0, 7 do b[#b + 1] = tonumber(hex:sub(15 - 2 * i, 16 - 2 * i), 16) end
		for _, x in ipairs(behaviour and BFILTERED or FILTERED) do b[#b + 1] = x end
		local cave, why = mr.patcher("aw_trace"):cave(name, site, string.char(unpack(b)))
		if not cave then return "failed: " .. tostring(why) end
	end
	mr.write(buf, 0x4f8, unit)
	AWH.b[name] = buf
	return "filtered"
end

local function rva(p) return mr.tostring(mr.sub(p, base)):sub(-7) end

function AWH.poll(name, who)
	local buf = AWH.b[name]
	local lo, hi = mr.tostring(mr.add(base, 0x1000)), mr.tostring(mr.add(base, 0x3a00000))
	local g = { sigs = {}, order = {}, last = mr.read_int32(buf, 0) }
	AWH.g = AWH.g or {}
	AWH.g[name] = g -- not AWH[name]: a hook called "b" used to overwrite the buffer table AWH.b (2026-11-01)
	bm:remove_process("awh_" .. name)
	bm:repeat_callback(function()
		local ok, e = pcall(function()
			local n = mr.read_int32(buf, 0)
			if n == g.last then return end
			g.last = n
			local tag = who(mr.read_pointer(buf, 8), mr.read_pointer(buf, 0x10), mr.read_pointer(buf, 0x18))
			if not tag then return end
			local ra = {}
			for k = 0, 0x400 - 8, 8 do
				local v = mr.tostring(mr.read_pointer(buf, 0x68 + k))
				if v > lo and v < hi and #ra < 16 then ra[#ra + 1] = rva(mr.read_pointer(buf, 0x68 + k)) end
			end
			local sig = tag .. " | " .. table.concat(ra, " ")
			local s = g.sigs[sig]
			if not s then s = { n = 0 } g.sigs[sig] = s g.order[#g.order + 1] = sig end
			s.n = s.n + 1
			local f = {}
			for off = 0, 0x3c, 4 do f[#f + 1] = string.format("%.1f", mr.read_float(buf, 0x28 + off)) end
			s.block = table.concat(f, " ")
			s.q = string.format("q0=%s q2=%s", mr.tostring(mr.read_pointer(buf, 0x28)), mr.tostring(mr.read_pointer(buf, 0x38)))
		end)
		if not ok then g.err = tostring(e) bm:remove_process("awh_" .. name) end
	end, 100, "awh_" .. name)
end

function AWH.report(name)
	local g = AWH.g[name]
	local out = { "hits=" .. mr.read_int32(AWH.b[name], 0) .. " err=" .. tostring(g.err) }
	for _, sig in ipairs(g.order) do
		local s = g.sigs[sig]
		out[#out + 1] = s.n .. "x " .. sig .. "\n    block: " .. s.block .. "\n    " .. s.q
	end
	return table.concat(out, "\n")
end

-- entity -> "u<i>body"/"u<i>man" for the player's units; the holder/command offsets a hook passes are subtracted by the caller
function AWH.entities()
	local map = {}
	local us = bm:get_player_army():units()
	for i = 1, us:count() do
		local o = mr.read_pointer(mr.ud_topointer(us:item(i)), 8)
		local n, data = mr.read_int32(o, 0xa4), mr.read_pointer(o, 0xa8)
		for k = 0, n - 1 do
			local m = mr.read_pointer(data, k * 8)
			map[mr.tostring(m)] = "u" .. i .. "man"
			local bd = mr.read_pointer(m, 0x2e0)
			if not mr.is_null(bd) then map[mr.tostring(bd)] = "u" .. i .. "body" end
		end
	end
	return map
end

return "artwalls hooks loaded"
