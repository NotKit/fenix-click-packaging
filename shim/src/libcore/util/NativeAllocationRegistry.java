package libcore.util;

import libcore.io.Posix;

import java.lang.ref.Cleaner;

/**
 * Frees a native peer once its Java object is unreachable. On ART this is a VM
 * service; here it is java.lang.ref.Cleaner plus a JNI call to the free function
 * pointer the caller registered.
 *
 * The size hint is kept only for the record: HotSpot has no equivalent of ART's
 * native allocation accounting, so it does not influence GC.
 */
public class NativeAllocationRegistry {
	private static final Cleaner CLEANER = Cleaner.create();
	private static boolean warned;

	private final long freeFunction;
	private final long size;

	public NativeAllocationRegistry(ClassLoader classLoader, long freeFunction, long size) {
		if (size < 0)
			throw new IllegalArgumentException("Invalid native allocation size: " + size);
		this.freeFunction = freeFunction;
		this.size = size;
	}

	/** @return a Runnable that frees the peer immediately, as libcore's does. */
	public Runnable registerNativeAllocation(Object referent, long nativePtr) {
		if (referent == null)
			throw new IllegalArgumentException("referent is null");
		if (nativePtr == 0)
			throw new IllegalArgumentException("nativePtr is null");
		Cleaner.Cleanable cleanable = CLEANER.register(referent, new Free(freeFunction, nativePtr));
		return cleanable::clean;
	}

	public long getSize() {
		return size;
	}

	/** Must not capture the referent, or nothing is ever collected. */
	private static final class Free implements Runnable {
		private final long freeFunction;
		private final long nativePtr;

		Free(long freeFunction, long nativePtr) {
			this.freeFunction = freeFunction;
			this.nativePtr = nativePtr;
		}

		@Override
		public void run() {
			if (!Posix.isAvailable()) {
				synchronized (Free.class) {
					if (!warned) {
						warned = true;
						System.err.println("port-shim: libportshim.so is not loaded (" + Posix.loadError()
						    + "), native peers will leak");
					}
				}
				return;
			}
			applyFreeFunction(freeFunction, nativePtr);
		}
	}

	public static native void applyFreeFunction(long freeFunction, long nativePtr);

	/** Hook for shim/tools checks: a real malloc and a counting free function. */
	public static final class SelfTest {
		private SelfTest() {}

		public static native long allocate(long size);

		public static native long freeFunction();

		public static native long freeCalls();
	}
}
