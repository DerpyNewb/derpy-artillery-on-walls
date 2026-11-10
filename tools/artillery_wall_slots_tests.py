"""Checks for the shipped native battlement caves. Run with gen_artillery_walls.py --selftest."""
import struct
import unicorn
from unicorn import x86_const as R


def scenarios(g, caves):
    names = ('wallgate', 'cursor', 'primary', 'solver', 'fronts', 'rear',
             'preview','preview_models','preview_order')
    assert all(n in caves for n in names), 'native battlement caves are missing'
    failures = []

    def run(name, listed=True, column=0, kind=0, row_count=24, flag=1, count=2, listed_index=0):
        u = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
        for base in (0x100000, 0x200000, 0x300000, 0x400000, 0x500000):
            u.mem_map(base, 0x10000)
        q = lambda p, v: u.mem_write(p, struct.pack('<Q', v))
        d = lambda p, v: u.mem_write(p, struct.pack('<I', v))
        f = lambda p, v: u.mem_write(p, struct.pack('<f', v))
        readq = lambda p: struct.unpack('<Q', u.mem_read(p, 8))[0]
        readf = lambda p: struct.unpack('<f', u.mem_read(p, 4))[0]
        block, unit, other, ctrl, group = 0x200000, 0x300000, 0x304000, 0x308000, 0x309000
        primary, vector, slots, parent, cmd, body = 0x30a000, 0x30b000, 0x30c000, 0x30d000, 0x30e000, 0x310000
        # Bodies need their +2e8/+910 fields, so map beyond the first object page.
        u.mem_map(0x310000, 0x10000)
        d(block + g.B['count'], listed_index+1)
        for i in range(listed_index+1):
            q(block + g.B['units']+i*8, unit if listed and i==listed_index else other+i*8)
        addresses = {k: 0x500100 + i * 0x100 for i, k in enumerate(g.CALLS)}
        for k, address in addresses.items():
            q(block + g.B[k], address)
        q(unit + 0x188, primary)
        d(unit + 0x184, count)
        d(unit + 0xa4, count * 7)
        d(unit + 0x3310, 1)
        q(unit + 0x3300, ctrl)
        q(ctrl, addresses['wall_vt'])
        q(ctrl + 0x18, unit)
        q(ctrl + 0xf8, group)
        d(ctrl + 0x154, count)
        q(ctrl + 0x158, vector)
        for i in range(count):
            b, s = body + i * 0x1000, slots + i * 0x58
            q(primary + i * 8, b)
            q(b + 0x2e8, unit)
            q(vector + i * 8, s)
            q(s + 0x18, parent)
            # Reverse assignments so ordinal mapping cannot accidentally pass ownership checks.
            q(s + 0x40, body + (count - 1 - i) * 0x1000)
            for off, value in ((0x20, i * 6.0), (0x24, 624.0), (0x28, -321.0)):
                f(s + off, value)
        q(parent + 0x60, slots)
        d(parent + 0x5c, row_count)
        d(parent + 0x30, kind)
        f(parent + 0x28, 0)
        f(parent + 0x2c, -1)
        sp = 0x408008 if name not in ('wallgate', 'cursor', 'primary') else 0x408000
        q(sp, 0x100f00)
        d(sp + 0x24, 0xcccccccc)
        f(sp + 0x38, 7)
        f(sp + 0x40, 9)
        inputs = {R.UC_X86_REG_RCX: unit, R.UC_X86_REG_RDX: cmd, R.UC_X86_REG_R8: unit,
                  R.UC_X86_REG_R9: 77, R.UC_X86_REG_RBX: ctrl, R.UC_X86_REG_RSI: unit,
                  R.UC_X86_REG_RDI: 0xabc, R.UC_X86_REG_RBP: sp - 0x3f,
                  R.UC_X86_REG_R12: 0x1212, R.UC_X86_REG_R13: 0x1313,
                  R.UC_X86_REG_R14: 0x1414, R.UC_X86_REG_R15: 0x1515}
        if name == 'fronts':
            inputs[R.UC_X86_REG_RBX] = primary
            q(primary, slots + column * 0x58)
            q(slots + column * 0x58 + 0x18, parent)
        if name in ('preview_models','preview_order'):
            inputs[R.UC_X86_REG_RDI] = unit
        for reg, value in inputs.items():
            u.reg_write(reg, value)
        u.reg_write(R.UC_X86_REG_RAX, 5)
        u.reg_write(R.UC_X86_REG_RSP, sp)
        d(inputs[R.UC_X86_REG_RBP] + 0x63, flag if name == 'rear' else 0xcccccccc)
        code = caves[name].replace(struct.pack('<Q', g.PLACEHOLDER), struct.pack('<Q', block))
        u.mem_write(0x100000, code)
        end = 0x100000 + len(code)
        exits = {addresses[k] for k in ('gate_cont','cursor_cont','prepare_cont','candidate_next','rear_next',
                                       'preview_cont','preview_models_cont','preview_order_cont')}
        state, calls = {}, []

        def hook(uc, address, size, data):
            if address in exits or address in (end, 0x100f00):
                state['at'] = address
                uc.emu_stop()
            elif address in {addresses[k] for k in ('fn_inf','fn_add')}:
                rsp = uc.reg_read(R.UC_X86_REG_RSP)
                calls.append((address, uc.reg_read(R.UC_X86_REG_RCX), uc.reg_read(R.UC_X86_REG_RDX)))
                assert (rsp + 8) % 16 == 0, 'native call stack misaligned'
                if address == addresses['fn_inf']:
                    uc.reg_write(R.UC_X86_REG_RAX, 0)
                # CA may overwrite every volatile register; retained context must survive.
                for reg in (R.UC_X86_REG_RCX,R.UC_X86_REG_RDX,R.UC_X86_REG_R8,R.UC_X86_REG_R9,
                            R.UC_X86_REG_R10,R.UC_X86_REG_R11):
                    uc.reg_write(reg, 0xdead)
                uc.reg_write(R.UC_X86_REG_RIP, readq(rsp))
                uc.reg_write(R.UC_X86_REG_RSP, rsp + 8)
        u.hook_add(unicorn.UC_HOOK_CODE, hook)
        u.emu_start(0x100000, 0, count=4000)
        assert 'at' in state, 'cave did not reach its continuation'
        assert u.reg_read(R.UC_X86_REG_RSP) == sp + (8 if state['at']==0x100f00 else 0), 'stack not restored'
        for reg in (R.UC_X86_REG_RBX,R.UC_X86_REG_RSI,R.UC_X86_REG_RBP,R.UC_X86_REG_R12,
                    R.UC_X86_REG_R13,R.UC_X86_REG_R14,R.UC_X86_REG_R15):
            if not (name=='preview_order' and reg==R.UC_X86_REG_RSI):
                assert u.reg_read(reg)==inputs[reg], 'nonvolatile register changed'
        if name not in ('primary','preview'):
            assert u.reg_read(R.UC_X86_REG_RDI)==inputs[R.UC_X86_REG_RDI]
        if name in ('solver','fronts','rear') and not calls:
            for reg in (R.UC_X86_REG_RCX,R.UC_X86_REG_RDX,R.UC_X86_REG_R8,R.UC_X86_REG_R9):
                assert u.reg_read(reg)==inputs[reg], 'native argument changed on the ordinary path'
        if name in ('wallgate','cursor'):
            assert state['at']==addresses['gate_cont' if name=='wallgate' else 'cursor_cont']
            assert bool(u.reg_read(R.UC_X86_REG_RAX)&0xff)==listed
            assert len(calls)==int(not listed)
        elif name=='primary':
            assert state['at']==(addresses['prepare_cont'] if listed else end)
            assert [c[2] for c in calls]==([body+i*0x1000 for i in range(count)] if listed else [])
        elif name=='solver':
            assert state['at']==end
            assert struct.unpack('<I',u.mem_read(sp+0x24,4))[0]==int(listed)
            assert (readf(sp+0x38),readf(sp+0x40))==((36,36) if listed else (7,9))
        elif name=='fronts':
            rejected=listed and (kind not in (0,1,2,0x12,0x13,0x14,0x15) or row_count<3 or column%3!=0)
            assert state['at']==(addresses['candidate_next'] if rejected else end)
        elif name=='rear':
            assert state['at']==(addresses['rear_next'] if flag else end)
            assert u.reg_read(R.UC_X86_REG_RAX)==5, 'rear loop count in rax was clobbered'
        elif name in ('preview','preview_models','preview_order'):
            assert state['at']==(addresses[name+'_cont'] if listed else end)
            assert u.reg_read(R.UC_X86_REG_RAX)==5, 'preview front count in eax must survive'
            reg={'preview':R.UC_X86_REG_RDI,'preview_models':R.UC_X86_REG_R9,'preview_order':R.UC_X86_REG_RSI}[name]
            assert u.reg_read(reg)==(count if listed else inputs[reg]), 'preview must count engines, not crew'

    cases = [(n, {'listed':listed}) for n in names if n!='rear' for listed in (False,True)]
    cases += [('fronts',opts) for opts in ({'column':1},{'column':3},{'kind':3},{'kind':0x12},{'row_count':2})]
    cases += [('rear',{'flag':0}),('rear',{'flag':1})]
    cases += [('primary',{'count':0}),('primary',{'count':8})]
    cases += [(n,{'count':c}) for n in ('preview','preview_models','preview_order') for c in (1,8)]
    for name, opts in cases:
        try:
            run(name, **opts)
        except (AssertionError, unicorn.UcError) as exc:
            import traceback
            line=traceback.extract_tb(exc.__traceback__)[-1].lineno
            failures.append(f'{name} {opts}: line {line}: {exc}')
    return failures


if __name__=='__main__':
    import gen_artillery_walls as g
    failures=scenarios(g,g.shipped_caves())
    for failure in failures:
        print('FAIL:',failure)
    raise SystemExit(bool(failures))
