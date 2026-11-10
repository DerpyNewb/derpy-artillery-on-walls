-- lua tools/artillery_walls_tests.lua (from the workspace root)
DERPY_AW_TEST = {}
local shipped = assert(io.open('Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua', 'rb'))
local source = shipped:read('*a'); shipped:close()
assert(not source:find('teleport_to_location', 1, true), 'teleport recovery must not ship')
assert(not source:find('mr.write(m.ptr,U.pos', 1, true), 'crew positions must not be written')
assert(not source:find('placement =', 1, true), 'native teleport cave must not ship')
out = function() end
memreader_plus = {}
math.huge = nil -- WH3's deterministic math table omits this field.
dofile('Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua')
local step = assert(DERPY_AW_TEST.exit_step)
local wall = assert(DERPY_AW_TEST.wall_step)
local function sample(now, split)
    return {now=now, move_order=true, ox=40, oz=0, ob=180, ow=8,
        bodies={{0,0,true,0},{0,0,not split,0}}}
end
for _,split in ipairs({false,true}) do
    local state={}
    assert(step(state,sample(0,split))==nil)
    assert(step(state,sample(19999,split))==nil)
    local a=assert(step(state,sample(20000,split)))
    assert(a[1]=='nudge' and a[2]==40 and a[3]==0 and a[4]==180 and a[5]==8)
    for t=20500,120000,500 do assert(step(state,sample(t,split))==nil, 'one retry per order; no later relocation') end
    local changed=sample(120500,split); changed.ox=50
    assert(step(state,changed)==nil)
    changed.now=140500; assert(step(state,changed)[1]=='nudge', 'a new destination gets one retry')
end
local state={}
local s=sample(0); s.wall_order=true; s.crew_wall=10; s.crew_total=14
step(state,s); s.now=20000
assert(step(state,s)[9]==true, 'a wall point retains its surface through the native queue')
s.now=60000; assert(step(state,s)==nil)
s=sample(0); s.ux,s.uz,s.ox=0,0,0
for t=0,60000,500 do s.now=t; assert(step({},s)==nil, 'an attack at the current position is left alone') end
s=sample(0); s.bodies={{-100,0,true,0}}; state={}; step(state,s)
s.now=60000; assert(step(state,s)==nil, 'distant orders are left alone')
local ws={key='wall',now=0,distance=20,engine_count=2,engines_arrived=0,crew_wall=0,crew_total=14,
    slots={{-3,-321},{3,-321}},nx=0,nz=-1,request={zone='wall'},motion={{'engine',0,0,0,0}}}
state={}; assert(wall(state,ws)==nil)
ws.now=5000; local a=assert(wall(state,ws))
assert(a[1]=='wall' and a[2]==ws.request, 'the retry retains the original native zone request')
ws.now=60000; assert(wall(state,ws)==nil, 'one zone retry')
state={}; ws.engines_arrived=2; ws.crew_wall=3
for t=0,60000,500 do ws.now=t; assert(wall(state,ws)==nil, 'every engine done on its slot: pushers below do not re-order it') end
-- runs 19 and 22: slots dropped at the stair head, engines spinning and wandering half a metre on the spot
local function spun(t) local j=(t/500)%2==0 and 0.45 or -0.45 return {{'b1',684.7+j,106.6,-326.0-j},{'b2',684.8-j,106.6,-335.8+j}} end
state={}; ws.engines_arrived=0; ws.distance=31
for t=0,4500,500 do ws.now=t; ws.motion=spun(t); assert(wall(state,ws)==nil) end
ws.now=5000; ws.motion=spun(5000); assert(wall(state,ws), 'a battery spinning on the spot is stalled')
local function walking(t) return {{'b1',600+t/1000,106.6,-339},{'b2',590+t/1000,106.6,-339}} end
state={}
for t=0,60000,500 do ws.now=t; ws.motion=walking(t); assert(wall(state,ws)==nil, 'a battery walking 1 m/s along the wall is not') end
local crew_step=assert(DERPY_AW_TEST.crew_step)
local function crew(d,rise)
    return {{key='engine',x=0,z=0,path=4,crew={{key='man',x=d,y=rise or 0,z=0,sx=0,sy=0,sz=0,resolved=true,manned=false}}}}
end
state={}; crew_step(state,0,crew(1)); crew_step(state,500,crew(1))
assert(#crew_step(state,2499,crew(1))==0)
assert(#crew_step(state,2500,crew(1))==1, 'nearby lagging crew may have their slot adjusted')
assert(#crew_step(state,60000,crew(1))==0, 'once while the engine stands')
-- a docked engine (path 0) whose pusher walks into the parapet for good; an idle man beside it is left alone
local function standing(walking) local e=crew(1); e[1].path=0; e[1].crew[1].walking=walking; return e end
state={}; for t=0,60000,500 do assert(#crew_step(state,t,standing(false))==0, 'idle crew of a standing engine are left alone') end
state={}; crew_step(state,0,standing(true)); crew_step(state,500,standing(true))
assert(#crew_step(state,2500,standing(true))==1, 'a man still walking at a standing engine has his spot moved to him')
for _,men in ipairs({crew(9),crew(1,-4)}) do
    state={}
    for t=0,60000,500 do assert(#crew_step(state,t,men)==0, 'distant crew keep walking without a lift') end
end
-- an engine stood 0.8 m short of its wall slot against the parapet (Altdorf, 2026-11-09)
local dock_step=assert(DERPY_AW_TEST.dock_step)
local function dock(o)
    local d={key='slot',walking=true,on_wall=true,x=578.2,y=106.6,z=-338.2,sx=578.2,sy=106.6,sz=-339}
    for k,v in pairs(o or {}) do d[k]=v end
    return {d}
end
state={}; assert(#dock_step(state,0,dock())==0)
assert(#dock_step(state,1499,dock())==0, 'not before it has stood still')
local got=dock_step(state,1500,dock())
assert(#got==1 and got[1].x==578.2 and got[1].z==-338.2, 'an engine stood short of its slot is settled where it stands')
assert(#dock_step(state,2000,dock())==0, 'and its clock starts again')
for _,o in ipairs({{walking=false},{on_wall=false},{x=580.4},{y=103.4}}) do
    state={}
    for t=0,10000,500 do assert(#dock_step(state,t,dock(o))==0, 'a finished, ground, distant or lower engine is left alone') end
end
state={}
for t=0,10000,500 do assert(#dock_step(state,t,dock{x=577+t/4000})==0, 'an engine still closing on its slot is left to walk') end
state={}; dock_step(state,0,dock()); dock_step(state,1000,dock{sx=578.4})
assert(#dock_step(state,1500,dock{sx=578.4})==0, 'a slot laid afresh restarts the clock')
dock_step(state,2000,{}); assert(next(state)==nil, 'a slot gone is forgotten')
-- an engine on a wall stood in its walk 2 m short of its slot, its crew gate shut (2026-11-09 run 6)
local gate_step=assert(DERPY_AW_TEST.gate_step)
local function gated(o)
    local g={key='engine',walking=true,on_wall=true,open=false,x=710.7,z=-338.9}
    for k,v in pairs(o or {}) do g[k]=v end
    return {g}
end
state={}; assert(#gate_step(state,0,gated())==0)
assert(#gate_step(state,1499,gated())==0, 'not before it has stood still')
assert(#gate_step(state,1500,gated())==1, 'a walking engine on a wall held by its crew gate is let go')
assert(#gate_step(state,2000,gated())==0, 'and its clock starts again')
assert(#gate_step(state,3500,gated())==1, 'and again while it is still held')
for _,o in ipairs({{open=true},{walking=false},{on_wall=false}}) do
    state={}
    for t=0,10000,500 do assert(#gate_step(state,t,gated(o))==0, 'a free, finished or ground engine is left to CA') end
end
state={}
for t=0,10000,500 do assert(#gate_step(state,t,gated{x=700+t/4000})==0, 'a moving engine is left alone') end
-- off a wall (run 21): a reaper held for good by a pusher 0.3 m short of his post, every pusher beside it
state={}; assert(#gate_step(state,0,gated{on_wall=false,pushers_near=true})==0)
assert(#gate_step(state,4999,gated{on_wall=false,pushers_near=true})==0, 'off a wall, CA gets longer to lay its pushers')
assert(#gate_step(state,5000,gated{on_wall=false,pushers_near=true})==1, 'then an engine with its pushers beside it is let go')
state={}
for t=0,20000,500 do assert(#gate_step(state,t,gated{on_wall=false,pushers_near=false})==0, 'off a wall, never without its crew (ask 1)') end
state={}
for t=0,20000,500 do assert(#gate_step(state,t,gated{on_wall=false,pushers_near=true,open=true})==0, 'an open gate is CA business') end
state={}; gate_step(state,0,gated{pushers_near=false})
assert(#gate_step(state,1500,gated{pushers_near=false})==1, 'on a wall the crew may be anywhere, and the wait is short')
local beside=assert(DERPY_AW_TEST.pushers_near)
local function reaper(crew) return {x=653.5,y=100.7,z=-191.9,crew=crew} end
local P={{index=0,x=654.1,y=100.7,z=-190.3},{index=1,x=655.4,y=100.7,z=-191.8},{index=2,x=651.1,y=100.7,z=-191.3}}
assert(beside(reaper(P)), 'the run 21 reaper: its three pushers 1.8-2.5 m off')
assert(beside(reaper({P[1],P[2],P[3],{index=5,x=600,y=95,z=-100}})), 'a gunner far off does not count')
assert(not beside(reaper({P[1],P[2],{index=2,x=651.1,y=100.7,z=-195}})), 'one pusher 3.3 m off is not beside it')
assert(not beside(reaper({P[1],P[2],{index=2,x=651.1,y=97.5,z=-191.3}})), 'nor one 3.2 m below it')
assert(not beside(reaper({{index=4,x=653.5,y=100.7,z=-191}})), 'no pusher at all is not a crew around it')
local function fake(key, art) return {unit_class = function() return 'art' end, type = function() return key end, is_artillery = function() return art end} end
assert(DERPY_AW_TEST.wall_gun(fake('wh_main_emp_art_great_cannon', true)), 'a walked cannon goes on a wall')
assert(not DERPY_AW_TEST.wall_gun(fake('wh3_main_cth_art_grand_cannon_0', true)), 'a gun an animal draws does not, artillery or not')
assert(DERPY_AW_TEST.wall_gun(fake('wh3_dlc23_chd_veh_magma_cannon', false)), 'a ridden one with no animal still does')
assert(DERPY_AW_TEST.wall_gun(fake('mod_art_unknown', true)), 'and a modded artillery unit')
print('artillery native retry and crew checks passed')

local calls,writes,allocations={},{},{}
local native=memreader_plus
native.base=0
native.add=function(p,n)return p+n end
native.tostring=tostring
native.read_uint8=function()return 0 end
native.read_pointer=function(p,off)
    if p==0x448f208 and off==0 then return 0x10000 end
    if p==0x10000 and off==0x468 then return 0x20000 end
    assert(p==0x20000 and off==0x644e8);return 0x30000
end
native.alloc=function(n)local p=0x40000+#allocations*0x100;allocations[#allocations+1]=p;return p end
native.write=function(p,off,v)writes[p+off]=v end
native.call=function(address,signature,...)
    local args={...};calls[#calls+1]={address=address,args=args}
    return (address==0x2dfcac4 or address==0x2ea33c8) and 1 or args[1]
end
DERPY_AW_TEST.queue_wall({ptr=0x1234},{zone=0x4567,x=-45,z=-321,surface=0x789a})
assert(calls[3].address==0x2eb09c8,'must construct DEFEND_BATTLEFIELD_ZONE, not generic MOVE')
local args=calls[3].args
assert(args[1]==allocations[2] and args[2]==allocations[1] and args[3]==0x4567 and args[4]==allocations[3])
assert(args[5]==0x789a and args[6]==0 and args[7]==0,'native wall constructor argument contract')
assert(calls[4].address==0x2dfcac4 and calls[4].args[1]==0x30000,'must use the typed wall queue writer')
assert(writes[allocations[3]]==-45 and writes[allocations[3]+4]==-321)
assert(calls[5].args[1]==allocations[2]+8 and calls[6].args[1]==allocations[1],'release both selection copies')
-- the queued wall MOVE after a wall-point drop, and the re-order: the order's own location block, order+0x40
-- (x, y, z, zero, surface, companion), is what a right-click left behind, so re-queuing it is a re-click
assert(DERPY_AW_TEST.ORDER_LOCATION == 0x40, 'a MOVE order keeps its location block at +0x40')
local BLOCK = 0x6000
native.uint32 = function(v) return v end
native.uint16 = function(v) return v end
native.is_null = function(p) return p == 0 end
local base_read = native.read_pointer
native.read_pointer = function(p, off)
    if p == BLOCK then return ({[0] = 0x11, [8] = 0x22, [0x10] = 0x789a, [0x18] = 0x9999})[off] end
    return base_read(p, off)
end
native.read_float = function(p, off)
    assert(p == BLOCK); return ({[0] = -44, [4] = 624, [8] = -321})[off]
end
calls, writes, allocations = {}, {}, {}
DERPY_AW_TEST.queue_move({ptr = 0x1234}, BLOCK, 180, 24)
assert(calls[3].address == 0x2eb0efc, 'must construct the facing MOVE goto_location_angle_width builds, not the wall zone order')
args = calls[3].args
assert(args[1] == allocations[2] and args[2] == allocations[1] and args[3] == allocations[3])
assert(writes[allocations[2] + 0xa8] == 32768, 'the facing goes in as a u16 heading, 180 degrees = 0x8000')
assert(writes[allocations[2] + 0xac] == 24, 'and the width as a float')
assert(writes[allocations[3]] == -44 and writes[allocations[3] + 4] == 624 and writes[allocations[3] + 8] == -321, 'the location block is the point the player clicked')
assert(writes[allocations[3] + 0x10] == 0x789a and writes[allocations[3] + 0x18] == 0x9999, 'with its wall surface and the companion pointer')
assert(calls[4].address == 0x2ea33c8 and calls[4].args[1] == 0x30000, 'pushed the way goto_location_angle_width pushes it')
assert(calls[5].args[1] == allocations[2] + 8 and calls[6].args[1] == allocations[1], 'release both copies')
native.read_pointer = function(p, off) if p == BLOCK and off == 0x10 then return 0 end return base_read(p, off) end
assert(not pcall(DERPY_AW_TEST.queue_move, {ptr = 0x1234}, BLOCK, 180, 24), 'a block with no wall surface is refused, not queued as a ground move')
print('artillery native wall queue contract passed')

-- Crew spots off the wall (2026-11-02). The game lays a spot as the gun's location plus an offset turned by the gun's
-- heading, x*cos+z*sin and z*cos-x*sin (exe+3086a80, sine and cosine from exe+1120900), and places it on the gun's
-- surface; behind a gun at a wall's edge it lands on the ground.
local spot_step, spot_try = assert(DERPY_AW_TEST.spot_step), assert(DERPY_AW_TEST.spot_try)
local spot_at_man, spot_keep = assert(DERPY_AW_TEST.spot_at_man), assert(DERPY_AW_TEST.spot_keep)
local function near(a, b) return math.abs(a - b) < 1e-4 end
local px, pz = spot_try(0.5, -6.2, 1)
assert(near(px, 0.3) and near(pz, -3.72), 'the first try pulls a pusher in along its own line')
local qx, qz = spot_try(0.5, -6.2, 2)
assert(math.sqrt(qx*qx + qz*qz) < math.sqrt(px*px + pz*pz), 'the second nearer still')
local lx, lz = spot_try(0.5, -6.2, 3)
local rx, rz = spot_try(0.5, -6.2, 4)
assert(math.abs(lx) > 2 and math.abs(lz) < 0.5, 'a turned try stands beside the gun, not behind it')
assert(near(lx, -rx), 'and the two turns are the two sides')
-- docked against a parapet, ahead of the gun is the stone (2026-11-09 runs 7 and 8)
for _, xz in ipairs({{0.5, -6.2}, {-0.5, -6.2}, {3.8, -3.3}, {-2.6, -3.4}, {1, 2}}) do
    for i = 1, 4 do local _, z = spot_try(xz[1], xz[2], i); assert(z <= 0, 'no try lays a spot ahead of the gun') end
end
local function spot(o) o.key = o.key or 's1'; o.x = o.x or 0.5; o.z = o.z or -6.2; o.on_wall = o.on_wall ~= false; o.live = o.live ~= false; return o end
local spots = {}
assert(#spot_step(spots, 0, {spot{off = false}}) == 0, 'a spot the game placed on the wall is left alone')
local w = spot_step(spots, 0, {spot{off = true}})
assert(#w == 1 and near(w[1][2], px) and near(w[1][3], pz), 'a spot placed off the wall gets the first try')
assert(#spot_step(spots, 399, {spot{x = px, z = pz, off = true}}) == 0, 'not judged before the game has placed it again')
w = spot_step(spots, 400, {spot{x = px, z = pz, off = true}})
assert(#w == 1 and near(w[1][2], qx), 'still off: the next try')
w = spot_step(spots, 800, {spot{x = qx, z = qz, off = true}}); assert(near(w[1][2], lx), 'then one side')
w = spot_step(spots, 1200, {spot{x = lx, z = lz, off = true}}); assert(near(w[1][2], rx), 'then the other')
w = spot_step(spots, 1600, {spot{x = rx, z = rz, off = true}})
assert(#w == 1 and near(w[1][2], qx) and near(w[1][3], qz), 'none lands: the nearest behind the gun is kept')
for t = 2000, 10000, 500 do assert(#spot_step(spots, t, {spot{x = qx, z = qz, off = true}}) == 0, 'and nothing more is tried') end
w = spot_step(spots, 10500, {spot{x = qx, z = qz, on_wall = false}})
assert(#w == 1 and near(w[1][2], 0.5) and near(w[1][3], -6.2), 'the gun off the wall gets CA spot back')
assert(#spot_step(spots, 11000, {spot{on_wall = false}}) == 0 and next(spots) == nil, 'once')
spots = {}
spot_step(spots, 0, {spot{off = true}})
assert(#spot_step(spots, 500, {spot{x = px, z = pz, off = false}}) == 0, 'a try that lands on the wall is kept')
w = spot_step(spots, 1000, {spot{x = 0.6, z = -6.0, off = true}})
assert(#w == 1 and near(w[1][2], 0.36) and near(w[1][3], -3.6), 'the game laid it out afresh: tried again from its new spot')
spots = {}
assert(#spot_step(spots, 0, {spot{off = false, failed = true}}) == 1, 'a spot the game could not place at all is moved')
assert(#spot_step({}, 0, {spot{off = true, live = false}}) == 0, 'a spot that is not live this tick is not judged')
spots = {}
spot_step(spots, 0, {spot{off = true}})
assert(#spot_step(spots, 500, {spot{x = px, z = pz, off = true, live = false}}) == 0, 'nor is a tried one: the game did not place it again')
assert(#spot_step({}, 0, {spot{off = true, on_wall = false}}) == 0, 'a gun on the ground keeps CA spots')
spots = {}
spot_step(spots, 0, {spot{off = true}})
spot_step(spots, 500, {})
assert(next(spots) == nil, 'a spot no longer listed drops its record')
-- the spot moved onto a man must be where the game will lay it: run his offset through the game's own turn
for _, turn in ipairs({0, 9000, 16384, 30000, 47000, 65000}) do
    local gun = {bx = 600, bz = -330, y = 106.6, turn = turn, on_wall = true}
    local m = {x = 602.3, z = -333.1, y = 106.9, on_wall = true, eng = gun}
    local ox, oz = spot_at_man(m)
    local a = turn * 2 * math.pi / 65536
    local c, sn = math.cos(a), math.sin(a)
    local front = (m.x - gun.bx) * sn + (m.z - gun.bz) * c
    if front <= 0 then
        assert(near(gun.bx + ox * c + oz * sn, m.x) and near(gun.bz + oz * c - ox * sn, m.z), 'the spot lands on the man at heading ' .. turn)
    else
        assert(oz == 0, 'a man ahead of the gun at heading ' .. turn .. ' gets a spot level with it, not under him')
    end
end
local gun = {bx = 0, bz = 0, y = 106.6, turn = 16384, on_wall = true}
local ox, oz = spot_at_man({x = 2, z = 0, y = 106.6, on_wall = true, eng = gun})
assert(near(ox, 0) and oz == 0, 'a gun facing east: a man two metres in front gets a spot level with the gun')
ox, oz = spot_at_man({x = -2, z = 0, y = 106.6, on_wall = true, eng = gun})
assert(near(ox, 0) and near(oz, -2), 'and a man two metres behind gets it under him')
assert(spot_at_man({x = 2, z = 0, y = 102, on_wall = true, eng = gun}) == nil, 'a man off the gun level keeps his native path')
assert(spot_at_man({x = 8, z = 0, y = 106.6, on_wall = true, eng = gun}) == nil, 'and one further than any spot')
assert(spot_at_man({x = 2, z = 0, y = 106.6, on_wall = false, eng = gun}) == nil, 'and one on the ground')
gun.on_wall = false
assert(spot_at_man({x = 2, z = 0, y = 106.6, on_wall = true, eng = gun}) == nil, 'a gun on the ground keeps CA spots')
spots = {}
spot_step(spots, 0, {spot{off = true}})
spot_keep(spots, 100, {key = 's1', x = px, z = pz}, 1.5, -0.5)
assert(#spot_step(spots, 600, {spot{x = 1.5, z = -0.5, off = true}}) == 0, 'a spot moved onto its man is not tried away from him')
w = spot_step(spots, 1100, {spot{x = 1.5, z = -0.5, on_wall = false}})
assert(near(w[1][2], 0.5) and near(w[1][3], -6.2), 'and still goes back to CA spot off the wall')
print('artillery crew spot rule checks passed')

-- the memory side: which slot fields are read, and the three writes that make the game place a spot again
local mem, wrote = {}, {}
native.read_pointer = function(p, off) return mem[p + off] or 0 end
native.read_int32 = function(p, off) return mem[p + off] or 0 end
native.read_float = function(p, off) return mem[p + off] or 0 end
native.read_uint8 = function(p, off) return mem[p + off] or 0 end
native.read_uint16 = function(p, off) return mem[p + off] or 0 end
native.is_null = function(p) return p == 0 end
native.write = function(p, off, v) mem[p + off] = v; wrote[#wrote + 1] = off end
local SLOT = DERPY_AW_TEST.SLOT
local UNIT, DATA, BODY, SLOTS, S = 0x100000, 0x200000, 0x300000, 0x400000, 0x500000
mem[UNIT + 0x184], mem[UNIT + 0x188], mem[DATA] = 1, DATA, BODY
mem[BODY + 0xc1c], mem[BODY + 0xc20], mem[SLOTS] = 1, SLOTS, S
mem[BODY + 0x920], mem[BODY + 0x914] = 0x777, 106.6
mem[BODY] = 0x3adee48 -- the walked gun's vtable (base 0 in this stub)
mem[S + 0x84], mem[S + 0x20], mem[S + 0x24], mem[S + 0x40], mem[S + 0x34], mem[S + 0xa8] = 1, 0.5, -6.2, 0, 90, 100
local unit = {ptr = UNIT, unit = {type = function() return 'gun' end}}
DERPY_AW_TEST.lay_spots(unit, 0)
assert(near(mem[S + 0x20], px) and near(mem[S + 0x24], pz), 'a spot on the ground under a gun on the wall: its offset pulled in')
assert(mem[S + 0x28] == math.floor(math.deg(math.atan2(px, pz)) * 65536 / 360 + 0.5) % 65536, 'its angle as CA computes it from the offset')
assert(mem[S + 0xa8] == 100 + 0x8000, 'and the heading it was placed for flipped, so the game places it again on the next tick')
mem[S + 0x40], mem[S + 0x34], wrote = 0x777, 106.6, {}
DERPY_AW_TEST.lay_spots(unit, 500)
assert(#wrote == 0, 'placed on the wall: left there')
mem[BODY + 0x920] = 0
DERPY_AW_TEST.lay_spots(unit, 1000)
assert(near(mem[S + 0x20], 0.5) and near(mem[S + 0x24], -6.2), 'the gun off the wall: CA offset back')
mem[BODY + 0x920], mem[S + 0x40], mem[S + 0x34], wrote = 0x777, 0x777, 104, {}
DERPY_AW_TEST.lay_spots(unit, 1500)
assert(#wrote == 0, 'a spot 2.6 m below its gun is a stair step, not the ground')
mem[S + 0x34] = 103
DERPY_AW_TEST.lay_spots(unit, 2000)
assert(#wrote > 0, 'more than three metres below is off the wall')
mem[BODY + 0xc1c], wrote = 48, {}
DERPY_AW_TEST.lay_spots(unit, 2400)
assert(#wrote > 0, 'a one-engine gun with 48 crew (Warp-Doom Magma Cannon, Queen Bess) is read')
mem[BODY + 0xc1c], wrote = 200, {}
DERPY_AW_TEST.lay_spots(unit, 2500)
assert(#wrote == 0, 'a slot count past any real table is not read')
mem[BODY], mem[BODY + 0xc1c], wrote = 0x390f998, 48, {}
DERPY_AW_TEST.lay_spots(unit, 2600)
assert(#wrote == 0, 'a ridden gun (Cathay, exe+390f998) is another class: none of its fields written')
mem[BODY] = 0x3adee48
-- crew posts in the parapet: a docked helstorm facing the wall (heading 180) whose deploy task walks into the stone
local B, ROWS, TL, T, TY1, TY23 = 0x600000, 0x610000, 0x620000, 0x630000, 0x640000, 0x650000
mem[B + 0xcbc], mem[B + 0xcc0], mem[TY1], mem[TY23] = 2, ROWS, 1, 23
mem[ROWS + 0x20], mem[ROWS + 0x40], mem[ROWS + 0x34], mem[ROWS + 0x3c], mem[ROWS + 0x44] = TY1, -1.37, 1.05, 1.05, 1.05
mem[ROWS + 0x50 + 0x20], mem[ROWS + 0x50 + 0x44] = TY23, 1.5
mem[B + 0xc0c], mem[B + 0xc10], mem[TL] = 1, TL, T
mem[T + 0x38], mem[T + 0x3c], mem[T + 0x48], mem[T + 0x50] = 1.32, 1.52, 0, -340.42 -- x 0: a task not yet started
mem[B + 0xd78], mem[B + 0xd80], mem[B + 0xd98], mem[B + 0xd9a] = 703.45, -338.9, 32768, 32768
local pull = assert(DERPY_AW_TEST.pull_crew_back)
assert(pull(B) == 2, 'one crew row and one task pulled back')
assert(mem[ROWS + 0x34] == 0 and mem[ROWS + 0x3c] == 0 and mem[ROWS + 0x44] == 0 and mem[ROWS + 0x40] == -1.37, 'the row level with the gun, its side kept')
assert(mem[ROWS + 0x50 + 0x44] == 1.5, 'the pusher layout row is left alone')
assert(mem[T + 0x3c] == 0 and near(mem[T + 0x48], 703.45 - 1.32) and near(mem[T + 0x50], -338.9), 'the task walks to a point level with the gun')
assert(pull(B) == 0, 'and nothing more once they are back')
mem[T + 0x3c], mem[T + 0x48] = -2.39, 5
assert(pull(B) == 0 and mem[T + 0x48] == 5, 'a post behind the gun is never touched')
mem[T + 0x3c] = -0.5
assert(pull(B) == 0 and mem[T + 0x3c] == -0.5, 'nor one just behind the face line')
-- turned off the wall (run 16): a cannon on a slot facing 180, turned to 203; its side post level with the gun is 0.7 m
-- into the stone, and so is the row the next deploy step's task is copied from
mem[B + 0xd98] = 36955 -- 203.0 degrees
local swung = math.rad(36955 * 360 / 65536 - 180)
mem[T + 0x38], mem[T + 0x3c], mem[T + 0x48], mem[T + 0x50] = -1.80, 0, 0, 0
assert(pull(B) == 2, 'a level post on the side the turn swings forward is pulled back, row and task')
assert(near(mem[T + 0x50], -338.9), 'the task walks to a point level with the gun along the wall')
assert(near(mem[T + 0x48], 703.45 + 1.80 * math.cos(swung)), 'on the wall line, straight back from where it stood')
assert(mem[T + 0x3c] < -0.6, 'behind the gun in its own frame')
assert(mem[ROWS + 0x44] < -0.45 and mem[ROWS + 0x34] == 0, 'the row copy with a side offset too; a copy with none stays level')
assert(pull(B) == 0, 'once')
mem[T + 0x38], mem[T + 0x3c] = -1.80, -1.2
assert(pull(B) == 0 and mem[T + 0x38] == -1.80, 'a post of a turned gun just behind the face line is left alone')
mem[T + 0x38], mem[T + 0x3c] = 1.80, 0.5
assert(pull(B) == 1 and mem[T + 0x3c] == 0, 'the side the turn swings back is still never let further forward than level')
mem[B + 0xd9a], mem[T + 0x38], mem[T + 0x3c] = 16384, -1.80, 0 -- a wall heading 90 degrees off: stale
pull(B)
assert(math.sqrt((mem[T + 0x38] + 1.80)^2 + mem[T + 0x3c]^2) <= 1.81, 'a stale wall heading moves a post at most its own distance')
-- laid 65 degrees off its slot (run 30): a bolt thrower facing 115 on a wall facing 180, two posts in the stone
mem[B + 0xd98], mem[B + 0xd9a] = math.floor(115 * 65536 / 360 + 0.5), 32768
mem[T + 0x38], mem[T + 0x3c], mem[T + 0x48], mem[T + 0x50] = 2.74, -1.58, 0, 0
assert(pull(B) >= 1 and near(mem[T + 0x50], -338.9), 'a post of a gun 65 degrees off its slot ends level along the wall')
assert(math.sqrt((mem[T + 0x38] - 2.74)^2 + (mem[T + 0x3c] + 1.58)^2) < 1.9 and mem[T + 0x3c] <= 0, 'moved under 2 m, still behind')
mem[B + 0xd98], mem[B + 0xd9a] = 32768, 32768
-- the turning point: a helstorm docked on a wall still anchored at its start-of-battle spot on the ground (run 11)
local A = 0x700000
local function placed(x, y, z) mem[A + 0xd78], mem[A + 0xd7c], mem[A + 0xd80], mem[A + 0xd88] = x, y, z, 0x777 end
local function anchored(x, y, z) mem[A + 0xd10], mem[A + 0xd14], mem[A + 0xd18], mem[A + 0xd20] = x, y, z, 0 end
local anchor = assert(DERPY_AW_TEST.anchor_step)
placed(683.58, 106.59, -338.99); anchored(428.29, 94.86, -257.6)
assert(anchor(A, true) == true, 'an engine on a wall anchored on the ground is re-anchored')
assert(mem[A + 0xd10] == 683.58 and mem[A + 0xd14] == 106.59 and mem[A + 0xd18] == -338.99 and mem[A + 0xd20] == 0x777,
    'to its placement block, surface and all')
assert(anchor(A, true) == false, 'once')
anchored(683.2, 106.59, -338.5)
assert(anchor(A, true) == false and mem[A + 0xd10] == 683.2, 'an anchor under the engine is left alone')
placed(600, 95, -300); anchored(640, 94, -320)
assert(anchor(A, false) == false and mem[A + 0xd10] == 640, 'on the ground, an anchor on the ground is CA business')
anchored(683.58, 106.59, -338.99)
assert(anchor(A, false) == true and mem[A + 0xd10] == 600, 'an engine come down from a wall is not turned toward the wall top')
-- the turn window: a helstorm on a wall slot facing 180 still centred on its heading on the ground at the start (run 12)
local base = assert(DERPY_AW_TEST.base_step)
mem[A + 0xd9a] = 26471 -- 145.4 degrees
assert(base(A, 32768) == true and mem[A + 0xd9a] == 32768, 'the turn window centred on the slot heading')
assert(base(A, 32768) == false and mem[A + 0xd9a] == 32768, 'once')
assert(base(A, 65535.7) == true and mem[A + 0xd9a] == 0, 'a heading that rounds to a full turn wraps to 0')
-- a deployed cannon shoved by a battery walking past: packed, nothing pending, its target handed over once (run 13)
local P = 0x800000
local packed = assert(DERPY_AW_TEST.stands_packed)
mem[P + 0x330 + 0xc4], mem[P + 0xc8c], mem[P + 0xce0], mem[P + 0xce4], mem[P + 0xcec] = 1, 1, 0, 0, 0
assert(packed(P) == true, 'packed with a handed-over target: stands packed')
for _, o in ipairs({0xce0, 0xce4, 0xcec}) do
    mem[P + o] = 0x10014
    assert(packed(P) == false, 'a deploy in progress or pending is left alone')
    mem[P + o] = 0
end
mem[P + 0x330 + 0xc4] = 0; assert(packed(P) == false, 'a command that has not handed over yet is left alone')
mem[P + 0x330 + 0xc4], mem[P + 0xc8c] = 1, 0; assert(packed(P) == false, 'no target, nothing to deploy for')
local still, wait = assert(DERPY_AW_TEST.still_step), assert(DERPY_AW_TEST.REDEPLOY_WAIT)
local function gun(ok, x) return {{key = 'gun', ok = ok, x = x or 578.4, z = -338.1, sx = 0, sz = 0}} end
state = {}; still(state, 0, gun(true), wait)
assert(#still(state, wait - 1, gun(true), wait) == 0 and #still(state, wait, gun(true), wait) == 1, 'asked again after standing packed for the wait')
state = {}; still(state, 0, gun(true), wait); still(state, 1000, gun(false), wait)
assert(#still(state, wait, gun(true), wait) == 0, 'a deploy in between restarts the clock')
-- multiplayer: walls stay vanilla, and caves left by an earlier single player battle get an empty unit list
local function install_in(multiplayer)
    local writes = {}
    bm = {is_multiplayer = function() return multiplayer end}
    memreader_plus = {base = 0, add = function(a, b) return a + b end, uint32 = function(n) return n end,
        hook_info = function() return {kind = 'cave', cave = 'cave'} end,
        read_pointer = function(at) assert(at == 'cave') return 'block' end,
        write = function(at, off, v) writes[#writes + 1] = {at, off, v} end}
    DERPY_AW_TEST = {}
    dofile('Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua')
    local block, why = DERPY_AW_TEST.install()
    return writes, block, why
end
local writes, block, why = install_in(true)
assert(#writes == 1 and writes[1][1] == 'block' and writes[1][2] == 0x18 and writes[1][3] == 0, 'multiplayer empties the unit list')
assert(block == nil and why:find('single player only', 1, true), 'multiplayer says why in the script log')
writes, block, why = install_in(false)
assert(#writes == 0 and why:find('native bridge', 1, true), 'single player goes on to install')
print('artillery crew spot memory contract passed')
