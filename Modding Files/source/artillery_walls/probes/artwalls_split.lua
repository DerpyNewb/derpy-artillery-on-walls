-- SPIKE: the split-state live check (2026-11-02): both batteries up on a wall, a ground order, and the state the
-- 22:40 report came from - one engine down with the rest still up - where the mover's crew-slot read threw every
-- tick. Loaded over the wh3 bridge once Deployed, after artwalls_probe.lua (AW) and artwalls_items.lua (AWI), with
-- AWT.uc[i] controllers from the deployed setup.
--   SP.run(ground)   wall order already queued by AW.move: waits for every engine up (or 240 s), gives the ground
--                    order through the unit's own controller, then watches 180 s; one row a second into SP.rows
--   SP.slots(b)      an engine body's slot table read one field at a time: the first field that throws, with
--                    every value read before it, so the failing read is pinned rather than guessed
--   SP.log           what happened, with battle times
local mr = _G.memreader_plus
local SP = _G.SP or {}
_G.SP = SP
SP.rows, SP.log, SP.seen = {}, {}, {}

local function note(s) SP.log[#SP.log + 1] = string.format('%d %s', bm:time_elapsed_ms(), s) end
local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end
local function unit(i) return bm:get_player_army():units():item(i) end

function SP.slots(b)
	local got, fail = {}, nil
	local function try(name, f)
		if fail then return nil end
		local ok, v = pcall(f)
		if not ok then fail = string.format('%s FAILED (%s)', name, tostring(v)) return nil end
		got[#got + 1] = name .. '=' .. (type(v) == 'userdata' and mr.tostring(v) or tostring(v))
		return v
	end
	local count = try('count', function() return mr.read_int32(b, 0xc1c) end)
	local slots = try('slots', function() return mr.read_pointer(b, 0xc20) end)
	if fail then return fail .. ' after ' .. table.concat(got, ' ') end
	if mr.is_null(slots) or count < 0 or count > 32 then return 'refused ' .. table.concat(got, ' ') end
	for j = 0, count - 1 do
		local s = try('s' .. j, function() return mr.read_pointer(slots, j * 8) end)
		local m = s and try('m' .. j, function() return mr.read_pointer(s, 0x10) end)
		if m and not mr.is_null(m) then try('mpos' .. j, function() return mr.read_float(m, 0x910) end) end
		if s then try('pt' .. j, function() return mr.read_float(s, 0x30) end) end
		if s then try('fl' .. j, function() return mr.read_uint8(s, 0x80) end) end
		if fail then return fail .. ' after ' .. table.concat(got, ' ') end
	end
	return 'ok ' .. count
end

-- engines of unit i: list of {body, up}
local function engines(i)
	local p = obj_of(unit(i))
	local d, n, out = mr.read_pointer(p, 0x188), mr.read_int32(p, 0x184), {}
	for k = 0, n - 1 do
		local b = mr.read_pointer(d, k * 8)
		out[#out + 1] = {b, not mr.is_null(mr.read_pointer(b, 0x920))}
	end
	return out
end

function SP.tick(ground)
	local now = bm:time_elapsed_ms()
	local a, b = AWI.sample(3), AWI.sample(4)
	SP.rows[#SP.rows + 1] = string.format('%d %s u3 e%d/%d c%d/%d%s | u4 e%d/%d c%d/%d%s', now, SP.stage,
		a.engines_up, a.engines, a.crew_up, a.crew, a.line, b.engines_up, b.engines, b.crew_up, b.crew, b.line)
	if SP.stage == 'climb' then
		if (a.engines_up == a.engines and b.engines_up == b.engines) or now - SP.t0 > 240000 then
			for _, i in ipairs({3, 4}) do
				local c = AWT.uc[i]
				c:take_control()
				c:goto_location_angle_width(battle_vector:new(ground.x, 0, ground.z), 180, 50)
				c:release_control()
			end
			SP.stage, SP.t1 = 'descent', now
			note(string.format('ground order to %.0f,%.0f; engines up u3 %d/%d u4 %d/%d', ground.x, ground.z, a.engines_up, a.engines, b.engines_up, b.engines))
		end
	elseif SP.stage == 'descent' then
		for _, i in ipairs({3, 4}) do
			local es, up, down = engines(i), 0, 0
			for _, e in ipairs(es) do if e[2] then up = up + 1 else down = down + 1 end end
			if up > 0 and down > 0 then
				for k, e in ipairs(es) do
					local key = mr.tostring(e[1])
					if not SP.seen[key] then
						local r = SP.slots(e[1])
						if r:sub(1, 2) ~= 'ok' then
							SP.seen[key] = true
							note(string.format('u%d e%d %s: %s', i, k, e[2] and 'up' or 'down', r))
						end
					end
				end
				if not SP.split_seen then SP.split_seen = true note(string.format('split: u%d %d up %d down', i, up, down)) end
			end
		end
		if (a.engines_up + b.engines_up + a.crew_up + b.crew_up == 0) or now - SP.t1 > 180000 then
			SP.stage = 'done'
			bm:remove_process('sp')
			note(string.format('done: u3 e%d/%d c%d/%d u4 e%d/%d c%d/%d', a.engines_up, a.engines, a.crew_up, a.crew, b.engines_up, b.engines, b.crew_up, b.crew))
		end
	end
end

function SP.run(ground)
	SP.stage, SP.t0 = 'climb', bm:time_elapsed_ms()
	bm:remove_process('sp')
	bm:repeat_callback(function()
		local ok, err = pcall(SP.tick, ground)
		if not ok then note('tick error ' .. tostring(err)) end
	end, 1000, 'sp')
	return 'running'
end

function SP.write(path)
	local f = assert(io.open(path, 'w'))
	f:write('--- log\n')
	for _, l in ipairs(SP.log) do f:write(l, '\n') end
	f:write('--- rows: t stage u3 engines_up/engines crew_up/crew per-engine x,y,z,wall | u4 ...\n')
	for _, l in ipairs(SP.rows) do f:write(l, '\n') end
	f:close()
	return path
end

return 'split probe loaded'
