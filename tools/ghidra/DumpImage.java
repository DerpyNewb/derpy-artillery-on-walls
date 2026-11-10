// Dump the program's initialized memory as one image file laid out by RVA, headless:
//   analyzeHeadless ... -postScript DumpImage.java <out.bin>
// A Ghidra project keeps its own copy of the imported exe's bytes, so a project imported before a game patch is the
// pre-patch snapshot that tools/exe_migrate.py diffs against. Uninitialized gaps are left as zero bytes.
//@category Derpy
import java.io.RandomAccessFile;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.MemoryBlock;

public class DumpImage extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length != 1) {
			printerr("usage: DumpImage.java <out.bin>");
			return;
		}
		long base = currentProgram.getImageBase().getOffset();
		try (RandomAccessFile out = new RandomAccessFile(args[0], "rw")) {
			out.setLength(0);
			for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
				if (!b.isInitialized() || !b.isLoaded()) continue;
				long rva = b.getStart().getOffset() - base;
				if (rva < 0) continue;
				byte[] bytes = new byte[(int) b.getSize()];
				b.getBytes(b.getStart(), bytes);
				out.seek(rva);
				out.write(bytes);
				println(String.format("%s rva %x size %x", b.getName(), rva, b.getSize()));
			}
		}
	}
}
