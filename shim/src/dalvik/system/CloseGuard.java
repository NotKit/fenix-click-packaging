package dalvik.system;

/**
 * Leak detector for unclosed resources. Nothing in the port depends on the
 * warnings, so this is a no-op that keeps the call sites compiling and running.
 */
public final class CloseGuard {
	private static final CloseGuard NOOP = new CloseGuard();

	private CloseGuard() {}

	public static CloseGuard get() {
		return NOOP;
	}

	public static void setEnabled(boolean enabled) {}

	public static boolean isEnabled() {
		return false;
	}

	public void open(String closer) {}

	public void openWithCallSite(String closer, String callsite) {}

	public void close() {}

	public void warnIfOpen() {}
}
