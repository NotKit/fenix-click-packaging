package dalvik.system;

import java.lang.reflect.Array;

/**
 * Minimal stand-in for ART's runtime handle.
 *
 * The "unpadded" and "non-movable" array variants exist to exploit ART's heap
 * layout; a plain array is a correct, if unoptimised, answer on HotSpot.
 */
public final class VMRuntime {
	private static final VMRuntime INSTANCE = new VMRuntime();

	private VMRuntime() {}

	public static VMRuntime getRuntime() {
		return INSTANCE;
	}

	public Object newUnpaddedArray(Class<?> componentType, int minLength) {
		return Array.newInstance(componentType, minLength);
	}

	public Object newNonMovableArray(Class<?> componentType, int length) {
		return Array.newInstance(componentType, length);
	}

	/** HotSpot arrays move and cannot be pinned; callers must handle 0. */
	public long addressOf(Object array) {
		return 0;
	}

	public boolean is64Bit() {
		return "64".equals(System.getProperty("sun.arch.data.model"));
	}

	public String vmLibrary() {
		return "libart.so";
	}
}
