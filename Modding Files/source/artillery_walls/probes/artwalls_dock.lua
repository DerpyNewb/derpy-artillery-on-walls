-- SPIKE (2026-11-09): docking runs. Needs artwalls_engines.lua (AWE) first.
--   AWX.st()          per battery: wall controller, moving, and per engine x,y,z, ground/surface, heading, manned, path, +0x18f
--   AWX.slots(i)      the wall controller's slots and the engine standing on each (path, action)
--   AWX.aim(i, x)     select card 100<i> alone and aim the camera at the parapet line at x
--   AWX.sample()      every 2 s model time into AWX.log: engine state and its pushers (slots 0-2)
--   AWX.dump(path)    write AWX.log to a file
local mr = _G.memreader_plus
local AWX = _G.AWX or {}
_G.AWX = AWX

local function unit(i) return bm:get_player_army():units():item(i) end
local function uptr(i) return mr.read_pointer(mr.ud_topointer(unit(i)), 8) end

function AWX.st()
	local out = {t = math.floor(bm:time_elapsed_ms() / 1000), phase = tostring(bm.current_phase)}
	for _, i in ipairs(_G.AW_UNITS or {3, 4}) do
		local rows = {}
		for _, b in ipairs(AWE.engines(i)) do
			local n, list, man = mr.read_int32(b, 0xc1c), mr.read_pointer(b, 0xc20), 0
			for k = 0, n - 1 do if mr.read_uint8(mr.read_pointer(list, k * 8), 0x81) == 1 then man = man + 1 end end
			rows[#rows + 1] = string.format('%.1f,%.1f,%.1f %s h%.0f m%d/%d p%d a%d', mr.read_float(b, 0x910), mr.read_float(b, 0x914),
				mr.read_float(b, 0x918), mr.is_null(mr.read_pointer(b, 0x920)) and 'g' or 's', mr.read_uint16(b, 0xb0) * 360 / 65536,
				man, n, mr.read_int32(b, 0x710), mr.read_uint8(b, 0x18f))
		end
		out['u' .. i] = string.format('ctl%d ord%d mv%s | %s', mr.read_int32(uptr(i), 0x3310), mr.read_int32(uptr(i), 0x2f88),
			tostring(unit(i):is_moving()), table.concat(rows, ' | '))
	end
	return out
end

function AWX.slots(i)
	local p = uptr(i)
	if mr.read_int32(p, 0x3310) ~= 1 then return 'no controller' end
	local c = mr.read_pointer(p, 0x3300)
	local n, d = mr.read_int32(c, 0x154), mr.read_pointer(c, 0x158)
	local rows = {}
	for k = 0, n - 1 do
		local s = mr.read_pointer(d, k * 8)
		local b = mr.read_pointer(s, 0x40)
		local bs = mr.is_null(b) and 'none' or string.format('%.1f,%.1f h%.0f p%d a%d act %s', mr.read_float(b, 0x910),
			mr.read_float(b, 0x918), mr.read_uint16(b, 0xb0) * 360 / 65536, mr.read_int32(b, 0x710), mr.read_uint8(b, 0x18f),
			mr.tostring(mr.read_pointer(b, 0x4a8)):sub(-7))
		rows[#rows + 1] = string.format('slot %.1f,%.1f <- %s', mr.read_float(s, 0x20), mr.read_float(s, 0x28), bs)
	end
	return rows
end

function AWX.aim(i, x)
	local p = find_uicomponent(core:get_ui_root(), 'battle_orders', 'battle_orders_pane', 'card_panel_docker', 'cards_panel', 'review_DY')
	for _, k in ipairs(_G.AW_UNITS or {3, 4}) do
		local c = find_uicomponent(p, tostring(1000 + k))
		local sel = c:CurrentState():find('selected') ~= nil
		if (k == i) ~= sel then c:SimulateLClick() end
	end
	bm:camera():move_to(battle_vector:new(x, 150, -300), battle_vector:new(x, 106.6, -338), 0, false, 0)
	return {find_uicomponent(p, '1003'):CurrentState(), find_uicomponent(p, '1004'):CurrentState()}
end

function AWX.sample()
	AWX.log = {}
	bm:remove_process('awx_sample')
	bm:repeat_callback(function() pcall(function()
		local t = math.floor(bm:time_elapsed_ms() / 1000)
		for _, i in ipairs(_G.AW_UNITS or {3, 4}) do for k, b in ipairs(AWE.engines(i)) do
			local sl, parts = mr.read_pointer(b, 0xc20), {}
			for j = 0, 2 do
				local s = mr.read_pointer(sl, j * 8)
				local m = mr.read_pointer(s, 0x10)
				if not mr.is_null(m) then parts[#parts + 1] = string.format('%.0f/%d/%s/%d', mr.read_float(m, 0x914), mr.read_int32(m, 0x710),
					mr.tostring(mr.read_pointer(m, 0x330)):sub(-4), mr.read_uint8(s, 0x81)) end
			end
			AWX.log[#AWX.log + 1] = string.format('%d u%de%d %.1f,%.1f,%.1f h%.0f p%d a%d cmd%s act%s | %s', t, i, k, mr.read_float(b, 0x910),
				mr.read_float(b, 0x914), mr.read_float(b, 0x918), mr.read_uint16(b, 0xb0) * 360 / 65536, mr.read_int32(b, 0x710),
				mr.read_uint8(b, 0x18f), mr.tostring(mr.read_pointer(b, 0x330)):sub(-4), mr.tostring(mr.read_pointer(b, 0x4a8)):sub(-4),
				table.concat(parts, ' '))
		end end
	end) end, 2000, 'awx_sample')
end

local function at(o) return mr.add(mr.add(mr.base, math.floor(o / 0x10000) * 0x10000), o % 0x10000) end

-- the mod's queue_wall, aimed at the battery's own zone and first slot: a native re-order, as the mover's retry sends
function AWX.requeue(i)
	local p = uptr(i)
	local c = mr.read_pointer(p, 0x3300)
	local first = mr.read_pointer(mr.read_pointer(c, 0x158), 0)
	local battle = mr.read_pointer(at(0x448f208), 0)
	local context = mr.read_pointer(battle, 0x468)
	assert(mr.read_uint8(context, 0x3b0) == 0 and mr.read_uint8(context, 0x3b1) == 0, 'battle queue is gated')
	local queue = mr.read_pointer(context, 0x644e8)
	local selection, command, point = mr.alloc(0x80), mr.alloc(0xb0), mr.alloc(8)
	mr.write(point, 0, mr.read_float(first, 0x20)); mr.write(point, 4, mr.read_float(first, 0x28))
	mr.call(at(0x2f36408), 'pointer(pointer)', selection)
	mr.call(at(0x2f3f044), 'pointer(pointer,pointer,uint8)', selection, p, 0)
	mr.call(at(0x2eb09c8), 'pointer(pointer,pointer,pointer,pointer,pointer,uint8,uint8)', command, selection,
		mr.read_pointer(c, 0x98), point, mr.read_pointer(first, 0x30), 0, 0)
	local result = mr.call(at(0x2dfcac4), 'uint8(pointer,pointer)', queue, command)
	mr.call(at(0x1bd3f4c), 'pointer(pointer)', mr.add(command, 8))
	mr.call(at(0x1bd3f4c), 'pointer(pointer)', selection)
	return mr.tostring(result)
end

-- per engine: walk state, locomotion state (638 idle, 640 arrived), +0x190 request, go-to fields, distance to its slot
function AWX.loco(i)
	local p = uptr(i)
	local c = mr.read_pointer(p, 0x3300)
	local n, d = mr.read_int32(c, 0x154), mr.read_pointer(c, 0x158)
	local rows = {}
	for k = 0, n - 1 do
		local s = mr.read_pointer(d, k * 8)
		local b = mr.read_pointer(s, 0x40)
		local dx, dz = 0, 0
		if mr.is_null(b) then rows[#rows + 1] = 'k' .. k .. ' no engine' else
		dx, dz = mr.read_float(b, 0x910) - mr.read_float(s, 0x20), mr.read_float(b, 0x918) - mr.read_float(s, 0x28)
		rows[#rows + 1] = string.format('k%d x%.2f z%.3f h%.0f p%d st %s 190 %d 18f %d act %s 9c %d 74 %d 78 %d d%.3f', k,
			mr.read_float(b, 0x910), mr.read_float(b, 0x918), mr.read_uint16(b, 0xb0) * 360 / 65536, mr.read_int32(b, 0x710),
			mr.tostring(mr.read_pointer(b, 0x160)):sub(-3), mr.read_uint8(b, 0x190), mr.read_uint8(b, 0x18f),
			mr.tostring(mr.read_pointer(b, 0x4a8)):sub(-4), mr.read_uint8(b, 0x544), mr.read_int32(b, 0x51c),
			mr.read_int32(b, 0x520), math.sqrt(dx * dx + dz * dz))
		end
	end
	return rows
end

-- the remedy under test: the go-to (vtable 3917110) of slot k aimed `back` m behind the engine, its slot moved
-- there too, and its started byte cleared so its own update issues a fresh walk
function AWX.unstick(i, k, back)
	local c = mr.read_pointer(uptr(i), 0x3300)
	local s = mr.read_pointer(mr.read_pointer(c, 0x158), k * 8)
	local b = mr.read_pointer(s, 0x40)
	assert(mr.tostring(mr.read_pointer(b, 0x4a8)):sub(-7) == '3917110', 'not a go-to')
	local a = math.rad(mr.read_uint16(b, 0xb0) * 360 / 65536)
	local x, z = mr.read_float(b, 0x910) - back * math.sin(a), mr.read_float(b, 0x918) - back * math.cos(a)
	mr.write(b, 0x4e8, x); mr.write(b, 0x4f0, z)
	mr.write(s, 0x20, x); mr.write(s, 0x28, z)
	mr.write(b, 0x544, mr.uint8(0))
	return string.format('-> %.2f,%.3f', x, z)
end

-- per engine: its command at +0x330 (vt 3ADF528 = the fire command, update exe+308d800: hands the engine its target
-- through exe+3077880 once, then sets +0xc4) and the deploy fields that command drives
function AWX.cmd(i)
	local function u32(p, o) return mr.read_uint16(p, o) + mr.read_uint16(p, o + 2) * 65536 end
	local rows = {}
	for k, b in ipairs(AWE.engines(i)) do
		local c = mr.add(b, 0x330) -- embedded in the body, its vtable is the first qword
		rows[#rows + 1] = string.format('e%d x%.1f cmd %s c4 %d b8 %d 78 %d c0 %x 30 %d 10 %d | c8c %d ce0 %x ce4 %x cec %x cfc %d/%d/%d/%d d54 %d', k,
			mr.read_float(b, 0x910), mr.tostring(mr.read_pointer(c, 0)):sub(-7), mr.read_uint8(c, 0xc4), mr.read_uint8(c, 0xb8),
			mr.read_int32(c, 0x78), u32(c, 0xc0), mr.read_int32(c, 0x30), mr.read_uint8(c, 0x10), mr.read_uint8(b, 0xc8c),
			u32(b, 0xce0), u32(b, 0xce4), u32(b, 0xcec), mr.read_uint8(b, 0xcfc), mr.read_uint8(b, 0xcfd), mr.read_uint8(b, 0xcfe),
			mr.read_uint8(b, 0xcff), mr.read_int32(b, 0xd54))
	end
	return rows
end

function AWX.dump(path)
	local f = assert(io.open(path, 'w'))
	for _, l in ipairs(AWX.log or {}) do f:write(l, '\n') end
	f:close()
	return #(AWX.log or {})
end

return 'artwalls dock probe loaded'
