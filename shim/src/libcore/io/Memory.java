package libcore.io;

import java.nio.ByteOrder;
import java.util.Objects;

/**
 * The two byte[] accessors android.os.ParcelFileDescriptor uses, and the eight
 * raw-address ones ART's libcore.io.Memory has.
 *
 * The address accessors have no caller in ATL or in Fenix. They are here
 * because protobuf-javalite asks whether they exist: Android.isOnAndroidDevice()
 * is "is libcore.io.Memory loadable", and UnsafeUtil then reflects
 * (Class.getMethod, so public members only) for exactly peekByte pokeByte
 * peekInt pokeInt peekLong pokeLong peekByteArray pokeByteArray at address type
 * long, to choose its 64-bit Android MemoryAccessor. A Memory that loads but
 * lacks them is the worst of the three states: protobuf believes it is on
 * Android and then has no accessor, so UnsafeUtil.MEMORY_ACCESSOR stays null and
 * the first message write NPEs in MessageSchema.isOneofPresent. ART's Memory has
 * all eight, so having them is what makes this shim answer the sniff the way the
 * phone does -- and the answer the phone gives is the one Fenix ships on. See
 * NOTES.md, "protobuf-javalite".
 *
 * Shaped exactly like ART's: the address accessors are native (libportshim.so,
 * shim/native/port_shim.c), with the byte-swap done in Java over private
 * *Native() calls, because a raw address is the one thing that cannot be
 * expressed in pure Java. Two consequences: nothing here needs sun.misc.Unsafe
 * -- which the java.* gate would reject anyway, since MethodHandle.invokeExact
 * has no declared descriptor to resolve; and if libportshim.so is missing, the
 * eight throw UnsatisfiedLinkError on call while still being *present*, which
 * is all protobuf's sniff looks at. The class initializer only asks Posix
 * whether the library loaded, and Posix's loader cannot throw, so this class
 * never lands in the error state -- one that would take ParcelFileDescriptor's
 * two accessors down with it and flip protobuf's detection at a distance.
 *
 * ART also has peekShort/pokeShort, the seven typed array copies, memmove and
 * unsafeBulkGet/Put. Nothing calls them and nothing reflects for them, so they
 * are not here.
 */
public final class Memory {
	/** Loads libportshim.so if it is there; Posix's loader swallows failure. */
	private static final boolean NATIVE_LOADED = Posix.isAvailable();

	private Memory() {}

	// --- the eight ART has at address type long ------------------------------

	public static native byte peekByte(long address);

	public static native void pokeByte(long address, byte value);

	public static int peekInt(long address, boolean swap) {
		int value = peekIntNative(address);
		return swap ? Integer.reverseBytes(value) : value;
	}

	public static void pokeInt(long address, int value, boolean swap) {
		pokeIntNative(address, swap ? Integer.reverseBytes(value) : value);
	}

	public static long peekLong(long address, boolean swap) {
		long value = peekLongNative(address);
		return swap ? Long.reverseBytes(value) : value;
	}

	public static void pokeLong(long address, long value, boolean swap) {
		pokeLongNative(address, swap ? Long.reverseBytes(value) : value);
	}

	/** Range-checked here rather than in C, unlike ART's. */
	public static void peekByteArray(long address, byte[] dst, int dstOffset, int byteCount) {
		Objects.checkFromIndexSize(dstOffset, byteCount, dst.length);
		peekByteArrayNative(address, dst, dstOffset, byteCount);
	}

	public static void pokeByteArray(long address, byte[] src, int srcOffset, int byteCount) {
		Objects.checkFromIndexSize(srcOffset, byteCount, src.length);
		pokeByteArrayNative(address, src, srcOffset, byteCount);
	}

	private static native int peekIntNative(long address);

	private static native void pokeIntNative(long address, int value);

	private static native long peekLongNative(long address);

	private static native void pokeLongNative(long address, long value);

	private static native void peekByteArrayNative(long address, byte[] dst, int dstOffset,
	    int byteCount);

	private static native void pokeByteArrayNative(long address, byte[] src, int srcOffset,
	    int byteCount);

	// --- the two android.os.ParcelFileDescriptor calls -----------------------

	public static int peekInt(byte[] src, int offset, ByteOrder order) {
		if (order == ByteOrder.BIG_ENDIAN) {
			return ((src[offset] & 0xff) << 24) | ((src[offset + 1] & 0xff) << 16)
			    | ((src[offset + 2] & 0xff) << 8) | (src[offset + 3] & 0xff);
		}
		return (src[offset] & 0xff) | ((src[offset + 1] & 0xff) << 8)
		    | ((src[offset + 2] & 0xff) << 16) | ((src[offset + 3] & 0xff) << 24);
	}

	public static void pokeInt(byte[] dst, int offset, int value, ByteOrder order) {
		if (order == ByteOrder.BIG_ENDIAN) {
			dst[offset] = (byte)(value >> 24);
			dst[offset + 1] = (byte)(value >> 16);
			dst[offset + 2] = (byte)(value >> 8);
			dst[offset + 3] = (byte)value;
		} else {
			dst[offset] = (byte)value;
			dst[offset + 1] = (byte)(value >> 8);
			dst[offset + 2] = (byte)(value >> 16);
			dst[offset + 3] = (byte)(value >> 24);
		}
	}
}
