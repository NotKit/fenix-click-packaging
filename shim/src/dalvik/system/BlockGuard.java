package dalvik.system;

/**
 * StrictMode's hook for slow calls. The desktop port has no policy to enforce,
 * so every thread gets the permissive one.
 */
public final class BlockGuard {
	public interface Policy {
		void onWriteToDisk();

		void onReadFromDisk();

		void onNetwork();

		void onUnbufferedIO();

		int getPolicyMask();
	}

	public static final Policy LAX_POLICY = new Policy() {
		@Override
		public void onWriteToDisk() {}

		@Override
		public void onReadFromDisk() {}

		@Override
		public void onNetwork() {}

		@Override
		public void onUnbufferedIO() {}

		@Override
		public int getPolicyMask() {
			return 0;
		}
	};

	private BlockGuard() {}

	public static Policy getThreadPolicy() {
		return LAX_POLICY;
	}

	public static void setThreadPolicy(Policy policy) {}
}
