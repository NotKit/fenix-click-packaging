package libcore.io;

/** Holder for the process-wide {@link Os}, as android.os.Process expects. */
public final class Libcore {
	public static final Os os = new PosixOs();

	private Libcore() {}

	static final class PosixOs implements Os {
		@Override
		public int getpid() {
			return (int)ProcessHandle.current().pid();
		}

		@Override
		public int getppid() {
			return ProcessHandle.current().parent().map(h -> (int)h.pid()).orElse(0);
		}

		@Override
		public int gettid() {
			// Without the JNI library the best available answer is the pid: callers use
			// this for thread priorities, and setting them on the process is harmless.
			return Posix.isAvailable() ? Posix.gettid() : getpid();
		}
	}
}
