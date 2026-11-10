-- SPIKE: artillery on walls, script-only (build 6acec6f4). Loaded over the wh3 bridge in a battle.
-- AW.status()         per unit: is_infantry, the record the climb check reads (unit+0x3db0), wall, position
-- AW.capture()        a wall position: the location block (+0x910, 0x20 bytes) of an Infernal Guard man on a wall section
-- AW.move(i, run)     the player's own BCQ_MULTIPLE_SELECTION_ORDER_MOVE for player unit i to the captured position
-- AW.patch(name, on)  P1a/P1b: the two climb checks skip is_infantry; P2a: is_infantry true for artillery; P2b: for war machines
local mr = _G.memreader_plus
assert(mr, "memreader Plus is not loaded")
local base = mr.base
-- game Lua numbers are float32: an RVA above 2^24 rounds (0x3014dca reads back as 0x3014dc8), so every address is
-- written as two exact halves, {high 16 bits, low 16 bits}
local function at(hl) return mr.add(mr.add(base, hl[1] * 0x10000), hl[2]) end

local AW = _G.AW or {}
_G.AW = AW

local BATTLE, SUB, QUEUE = {0x448, 0x0da0}, 0x468, 0x644e8
local SEL_INIT, SEL_ADD, CMD_BUILD, PUSH, DTOR = {0x2f2, 0xefc8}, {0x2f3, 0x7be4}, {0x2ea, 0x9a94}, {0x1ca, 0xe60c}, {0x1bc, 0xd8ac}
local LOC, SURF = 0x910, 0x920
local MODELS_N, MODELS_DATA = 0xa4, 0xa8
local REC, REC_RADIUS, REC_CLIMB = 0x3db0, 0x5c, 0xb4

local c = string.char -- Lua 5.1 has no \x escapes
local PATCHES = {
	P1a = {{0x301, 0x4dca}, c(0xe8, 0x8d, 0xf4, 0x01, 0x00), c(0xb0, 0x01, 0x90, 0x90, 0x90)}, -- climb check A: call is_infantry -> mov al, 1
	P1b = {{0x301, 0xd6d6}, c(0xe8, 0x81, 0x6b, 0x01, 0x00), c(0xb0, 0x01, 0x90, 0x90, 0x90)}, -- climb check B
	P2a = {{0x303, 0x429a}, c(0x74, 0x55), c(0xeb, 0x55)}, -- is_infantry: artillery branch always true
	P2b = {{0x303, 0x42ae}, c(0x75, 0xec), c(0x75, 0x41)}, -- is_infantry: a war machine goes to true
	P3 = {{0x305, 0x9540}, c(0x75, 0x23), c(0x90, 0x90)}, -- man slot 0xa0 (can use links): ignore the entity's +0x2a0 (false on a vehicle body)
}
AW.on = AW.on or {}

local function obj_of(unit) return mr.read_pointer(mr.ud_topointer(unit), 8) end
local function units() return bm:get_player_army():units() end

function AW.patch(name, on)
	local p = PATCHES[name]
	local from, to = p[2], p[3]
	if not on then from, to = to, from end
	local r = mr.patch(at(p[1]), from, to)
	if r ~= nil then AW.on[name] = on end
	return r ~= nil
end

function AW.status()
	local out = {}
	local us = units()
	for i = 1, us:count() do
		local u = us:item(i)
		local o = obj_of(u)
		local rec = mr.read_pointer(o, REC)
		local p = u:position()
		local inf = "?"
		pcall(function() inf = tostring(u:is_infantry()) end)
		out[#out + 1] = string.format("%d %s inf=%s rec_r=%.2f rec_climb=%d wall=%s pos=(%.1f, %.1f, %.1f) above=%.1f",
			i, (u:type():gsub("wh3_[%w]+_chd_", "")), inf, mr.read_float(rec, REC_RADIUS), mr.read_uint8(rec, REC_CLIMB),
			tostring(u:is_on_top_of_wall()), p:get_x(), p:get_y(), p:get_z(), p:get_y() - bm:get_terrain_height(p:get_x(), p:get_z()))
	end
	local on = {}
	for k, v in pairs(AW.on) do if v then on[#on + 1] = k end end
	table.sort(on)
	out.patches = table.concat(on, ",")
	return out
end

-- the first live man of unit i standing on a wall section (+0x920 not null)
function AW.capture(i)
	local o = obj_of(units():item(i or 2))
	local n, data = mr.read_int32(o, MODELS_N), mr.read_pointer(o, MODELS_DATA)
	for k = 0, n - 1 do
		local m = mr.read_pointer(data, k * 8)
		local surf = mr.read_pointer(m, SURF)
		if not mr.is_null(surf) then
			AW.POS = AW.POS or mr.alloc(0x20)
			for off = 0, 8, 4 do mr.write(AW.POS, off, mr.read_float(m, LOC + off)) end
			mr.write(AW.POS, 0xc, mr.uint32(0))
			mr.write(AW.POS, 0x10, surf)
			mr.write(AW.POS, 0x18, mr.read_pointer(m, LOC + 0x18))
			return string.format("man %d of %d at (%.1f, %.1f, %.1f) surface %s id %d", k, n,
				mr.read_float(m, LOC), mr.read_float(m, LOC + 4), mr.read_float(m, LOC + 8), mr.tostring(surf), mr.read_int32(surf, 0x28))
		end
	end
	return "no man of unit " .. tostring(i or 2) .. " stands on a wall section"
end

function AW.move(i, run)
	assert(AW.POS, "capture a wall position first")
	local g = mr.read_pointer(at(BATTLE), 0)
	local b = mr.read_pointer(g, SUB)
	assert(mr.read_uint8(b, 0x3b0) == 0 and mr.read_uint8(b, 0x3b1) == 0, "the queue is gated")
	local q = mr.read_pointer(b, QUEUE)
	local sel, cmd = mr.alloc(0x80), mr.alloc(0xb0)
	mr.call(at(SEL_INIT), "pointer(pointer)", sel)
	mr.call(at(SEL_ADD), "pointer(pointer, pointer, uint8)", sel, obj_of(units():item(i)), 0)
	mr.call(at(CMD_BUILD), "pointer(pointer, pointer, pointer, uint8, uint8)", cmd, sel, AW.POS, run and 1 or 0, 0)
	local ok = mr.call(at(PUSH), "uint8(pointer, pointer)", q, cmd)
	mr.call(at(DTOR), "pointer(pointer)", mr.add(cmd, 8))
	mr.call(at(DTOR), "pointer(pointer)", sel)
	return ok
end

return "artwalls probe loaded"
