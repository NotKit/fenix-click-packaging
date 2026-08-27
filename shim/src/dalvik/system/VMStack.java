package dalvik.system;

/**
 * The one VMStack entry point in Fenix's bytecode, over {@link StackWalker}.
 *
 * ART walks managed frames; StackWalker walks JVM frames, so a call ART would
 * hide (a bridge, an inlined accessor) can shift the answer by a frame. The
 * single caller (com.google.android.gms.internal.fido.zzui.zzq) catches every
 * throwable and treats null as "not on Android", so a shifted or null answer is
 * harmless there.
 */
public final class VMStack {
	private VMStack() {}

	/** The class of the caller's caller's caller; libcore's NthCallerVisitor(3). */
	public static Class<?> getStackClass2() {
		return nthCaller(3);
	}

	/** The class of the caller's caller; libcore's NthCallerVisitor(2). */
	public static Class<?> getStackClass1() {
		return nthCaller(2);
	}

	public static ClassLoader getCallingClassLoader() {
		Class<?> caller = nthCaller(2);
		return caller == null ? null : caller.getClassLoader();
	}

	/**
	 * @param n libcore's frame index, counting this class's own entry point as 0.
	 *          The walk starts at nthCaller itself, so the entry point is at 1.
	 */
	private static Class<?> nthCaller(int n) {
		return StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE)
		    .walk(frames -> frames.skip(n + 1L).findFirst()
		        .map(StackWalker.StackFrame::getDeclaringClass).orElse(null));
	}
}
