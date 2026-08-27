package dalvik.system;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

/** Only the CPU-time query android.os.Debug forwards to. */
public final class VMDebug {
	private static final ThreadMXBean THREADS = ManagementFactory.getThreadMXBean();

	private VMDebug() {}

	public static long threadCpuTimeNanos() {
		return THREADS.isCurrentThreadCpuTimeSupported() ? THREADS.getCurrentThreadCpuTime() : -1;
	}
}
