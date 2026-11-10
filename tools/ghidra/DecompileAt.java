// Decompile functions by RVA, headless: analyzeHeadless ... -postScript DecompileAt.java <out.c> <rva> [<rva> ...]
// Each RVA (hex, as exe+RVA in the docs) is disassembled from, made a function if none holds it, and decompiled to
// <out.c>. Works on a program imported with -noanalysis: the decompiler's own local analysis is enough for one function.
// Driven by tools/ghidra_decompile.py; see docs/BATTLE_ENGINE_RE.md.
//@category Derpy
import java.io.FileWriter;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DecompileAt extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 2) {
			printerr("usage: DecompileAt.java <out.c> <rva> [<rva> ...]");
			return;
		}
		DecompInterface dec = new DecompInterface();
		dec.openProgram(currentProgram);
		try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
			for (int i = 1; i < args.length; i++) {
				long rva = Long.parseLong(args[i].replaceFirst("^(?i)(exe\\+)?(0x)?", ""), 16);
				Address at = currentProgram.getImageBase().add(rva);
				if (getInstructionAt(at) == null) disassemble(at);
				Function f = getFunctionContaining(at);
				if (f == null) f = createFunction(at, null);
				if (f == null) {
					out.printf("// exe+%x: no function could be made here%n%n", rva);
					continue;
				}
				DecompileResults r = dec.decompileFunction(f, 120, monitor);
				// no body size: without analysis Ghidra records a function's body as its entry alone, and the
				// decompiler follows the flow by itself
				long start = f.getEntryPoint().subtract(currentProgram.getImageBase());
				out.printf("// exe+%x (function exe+%x)%n", rva, start);
				if (r.decompileCompleted()) out.println(r.getDecompiledFunction().getC());
				else out.printf("// decompile failed: %s%n%n", r.getErrorMessage());
			}
		}
		dec.dispose();
	}
}
