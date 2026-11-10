-- Diagnostic counters for build 6ae2a00b; no movement changes.
local mr=memreader_plus
AWC=AWC or {buffers={}}
local bytes={156,80,65,82,72,184,136,119,102,85,68,51,34,17,65,186,8,0,0,0,72,57,8,116,11,72,131,192,16,65,255,202,117,242,235,3,255,64,8,65,90,88,157}
function AWC.hook(name,hi,lo)
    local site=mr.add(mr.add(mr.base,hi*0x10000),lo)
    local info=mr.hook_info(site)
    local buf
    if info then buf=mr.read_pointer(info.cave,6) else
        buf=mr.game_alloc(128)
        local b={unpack(bytes)}; local hex=mr.tostring(buf)
        for i=0,7 do b[6+i+1]=tonumber(hex:sub(15-2*i,16-2*i),16) end
        assert(mr.patcher('aw_counts'):cave(name,site,string.char(unpack(b))))
    end
    AWC.buffers[name]=buf
    local k=0
    for _,i in ipairs({3,4}) do for _,body in ipairs(AWE.engines(i)) do
        assert(k<8); mr.write(buf,k*16,body);mr.write(buf,k*16+8,mr.uint32(0));k=k+1
    end end
end
function AWC.report()
    local out={}
    for name,buf in pairs(AWC.buffers) do
        local rows={}
        for k=0,7 do rows[#rows+1]={body=mr.tostring(mr.read_pointer(buf,k*16)),count=mr.read_int32(buf,k*16+8)} end
        out[name]=rows
    end
    return out
end
AWC.hook('fire_virtual',0x307,0x850c)
AWC.hook('fire_init',0x307,0x062c)
return AWC.report()
