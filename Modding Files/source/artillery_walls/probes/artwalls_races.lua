-- SPIKE: every artillery unit of the player's army up the wall and down again, one at a time, with the shipped
-- mover running. Loaded over the wh3 bridge once the battle is Deployed (after artwalls_probe.lua for AW.capture /
-- AW.move). Player unit 2 must be infantry: it is put on the roof point so a wall location block can be captured.
-- AWR.start(roof, ground, cap)  roof = {x=,z=} the wall point, ground = {x=,z=} where a battery waits and returns
--                               to, cap = seconds allowed each way (default 150). Units 3.. that are artillery.
-- AWR.status()                  one line per unit so far
-- AWR.write(path)               the results and the 1 s trace
local mr = _G.memreader_plus
assert(mr, "memreader Plus is not loaded")
local AWR = _G.AWR or {}
_G.AWR = AWR

local function obj_of(u) return mr.read_pointer(mr.ud_topointer(u), 8) end

-- engines up / crew up / every engine within 5 m of a crewman, for unit i
local function sample(i)
	local u = bm:get_player_army():units():item(i)
	local p = obj_of(u)
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
	return {engines = n, engines_up = eup, crew = total, crew_up = up, line = line}
end

function AWR.start(roof, ground, cap)
	cap = (cap or 150) * 1000
	local units = bm:get_player_army():units()
	AWR.results, AWR.trace, AWR.queue, AWR.done = {}, {}, {}, false
	for i = 3, units:count() do
		local u = units:item(i)
		if u:is_artillery() or u:unit_class() == 'art' then AWR.queue[#AWR.queue + 1] = i end
	end
	-- everyone halted; the enemy out of the way and unkillable; the infantry on the roof point
	AWT = AWT or {uc = {}, enemy = {}}
	for i = 1, units:count() do
		local c = bm:get_player_army():create_unit_controller()
		c:add_units(units:item(i)); c:take_control(); c:halt(); c:fire_at_will(false)
		AWT.uc[i] = c
	end
	for a = 1, bm:alliances():count() do
		if a ~= bm:get_player_alliance_num() then
			local armies = bm:alliances():item(a):armies()
			for j = 1, armies:count() do
				local army = armies:item(j)
				local c = army:create_unit_controller()
				for k = 1, army:units():count() do c:add_units(army:units():item(k)) end
				c:take_control(); c:halt(); c:set_invincible(true)
				c:teleport_to_location(battle_vector:new(-40, 0, -520), 0, 100)
				AWT.enemy[#AWT.enemy + 1] = c
			end
		end
	end
	AWT.uc[2]:teleport_to_location(battle_vector:new(roof.x, 0, roof.z), 180, 50)
	for _, i in ipairs(AWR.queue) do
		AWT.uc[i]:teleport_to_location(battle_vector:new(ground.x - 60, 0, ground.z - 40), 180, 30)
	end
	local state, cur, t0, step = 'capture', nil, nil, nil
	bm:remove_process('awr')
	bm:repeat_callback(function()
		local ok, err = pcall(function()
			local now = bm:time_elapsed_ms()
			if state == 'capture' then
				assert(AW.capture(2))
				state = 'next'
			elseif state == 'next' then
				cur = table.remove(AWR.queue, 1)
				if not cur then AWR.done = true; bm:remove_process('awr'); return end
				local u = units:item(cur)
				AWR.results[#AWR.results + 1] = {index = cur, type = u:type(), engines = sample(cur).engines, crew = sample(cur).crew}
				AWT.uc[cur]:teleport_to_location(battle_vector:new(ground.x, 0, ground.z), 180, 50)
				AWT.uc[cur]:release_control()
				state, t0 = 'placed', now
			elseif state == 'placed' and now - t0 >= 3000 then
				AW.move(cur, false)
				state, t0, step = 'up', now, 'up'
			elseif state == 'up' or state == 'down' then
				local s = sample(cur)
				local r = AWR.results[#AWR.results]
				AWR.trace[#AWR.trace + 1] = string.format('%d u%d %s cw%d/%d%s', now, cur, state, s.crew_up, s.crew, s.line)
				if state == 'up' then
					if s.engines_up == s.engines and not r.engines_up then r.engines_up = (now - t0) / 1000 end
					if s.engines_up == s.engines and s.crew_up == s.crew then r.all_up = (now - t0) / 1000 end
					if r.all_up or now - t0 >= cap then
						r.up_line = s.line
						-- halt first: a ground order given under the native wall-zone controller a wall transfer leaves
						-- behind was ignored for 150 s (Dwarf cannon, 2026-11-01) and the mover stayed in wall mode
						AWT.uc[cur]:take_control()
						AWT.uc[cur]:halt()
						AWT.uc[cur]:goto_location_angle_width(battle_vector:new(ground.x, 0, ground.z), 180, 50)
						AWT.uc[cur]:release_control()
						state, t0 = 'down', now
					end
				else
					if s.engines_up == 0 and not r.engines_down then r.engines_down = (now - t0) / 1000 end
					if s.engines_up == 0 and s.crew_up == 0 then r.all_down = (now - t0) / 1000 end
					if r.all_down or now - t0 >= cap then
						r.down_line = s.line
						AWT.uc[cur]:take_control(); AWT.uc[cur]:halt()
						AWT.uc[cur]:teleport_to_location(battle_vector:new(ground.x - 60, 0, ground.z - 40), 180, 30)
						state = 'next'
					end
				end
			end
		end)
		if not ok then AWR.err = tostring(err); bm:remove_process('awr') end
	end, 1000, 'awr')
	return string.format('%d artillery units queued: %s', #AWR.queue, table.concat(AWR.queue, ','))
end

function AWR.status()
	local out = {done = AWR.done, err = AWR.err, left = #AWR.queue, t = bm:time_elapsed_ms()}
	for _, r in ipairs(AWR.results) do
		out[#out + 1] = string.format('u%d %s engines %d crew %d | up: engines %s all %s | down: engines %s all %s', r.index, r.type, r.engines, r.crew, tostring(r.engines_up), tostring(r.all_up), tostring(r.engines_down), tostring(r.all_down))
	end
	return out
end

function AWR.write(path, note)
	local f = assert(io.open(path, 'w'))
	f:write(note or '', '\n')
	for _, l in ipairs(AWR.status()) do if type(l) == 'string' then f:write(l, '\n') end end
	f:write('--- trace: t unit phase crew_up/crew then per engine x,y,z,wall\n')
	for _, l in ipairs(AWR.trace) do f:write(l, '\n') end
	f:close()
	return #AWR.trace
end

return 'artillery races probe loaded'
