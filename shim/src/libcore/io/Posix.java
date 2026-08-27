package libcore.io;

import android.system.ErrnoException;

import java.io.FileDescriptor;

/**
 * The shim's JNI back end (libportshim.so, built from shim/native/port_shim.c).
 *
 * Only the calls that cannot be expressed in pure Java live here: turning a
 * java.io.FileDescriptor into an int and back, and the fd syscalls
 * android.system.Os exposes. Everything the JDK can already do is implemented in
 * Java instead, so the shim still works when the library is missing.
 */
public final class Posix {
	/** Absolute path override, for when java.library.path is not set up yet. */
	public static final String PATH_PROPERTY = "port.shim.native.path";

	private static final boolean LOADED = load();
	private static String loadError;

	private Posix() {}

	private static boolean load() {
		String path = System.getProperty(PATH_PROPERTY);
		if (path != null && !path.isEmpty())
			return tryLoad(path, true);
		// firefox-atl deviation from linux-port/shim: the launcher gives the shim
		// jar a -c entry but nothing puts its directory on java.library.path, so
		// fall back to the .so build.sh writes next to the jar.
		return tryLoad("portshim", false) || tryLoad(besideTheJar(), true);
	}

	private static boolean tryLoad(String what, boolean absolute) {
		if (what == null)
			return false;
		try {
			if (absolute)
				System.load(what);
			else
				System.loadLibrary(what);
			return true;
		} catch (Throwable t) {
			loadError = loadError == null ? String.valueOf(t) : loadError + "; " + t;
			return false;
		}
	}

	/** libportshim.so as build.sh installs it: beside shim.jar. */
	private static String besideTheJar() {
		try {
			java.security.CodeSource source =
			    Posix.class.getProtectionDomain().getCodeSource();
			if (source == null || source.getLocation() == null)
				return null;
			java.io.File jar = new java.io.File(source.getLocation().toURI());
			java.io.File dir = jar.isDirectory() ? jar : jar.getParentFile();
			java.io.File so = new java.io.File(dir, "libportshim.so");
			return so.isFile() ? so.getPath() : null;
		} catch (Throwable t) {
			return null;
		}
	}

	public static boolean isAvailable() {
		return LOADED;
	}

	/** Why the library could not be loaded, or null if it was. */
	public static String loadError() {
		return loadError;
	}

	public static void require(String function) throws ErrnoException {
		if (!LOADED)
			throw new ErrnoException(function + " (libportshim.so not loaded: " + loadError + ")", 38 /* ENOSYS */);
	}

	public static native int gettid();

	public static native int fdOf(FileDescriptor fd);

	public static native FileDescriptor fdFor(int fd);

	public static native void setFd(FileDescriptor fd, int value);

	public static native int open(String path, int flags, int mode) throws ErrnoException;

	public static native int dup(int fd) throws ErrnoException;

	public static native int[] pipe() throws ErrnoException;

	public static native int[] socketpair(int domain, int type, int protocol) throws ErrnoException;

	public static native long lseek(int fd, long offset, int whence) throws ErrnoException;

	public static native int read(int fd, byte[] bytes, int off, int len) throws ErrnoException;

	public static native int write(int fd, byte[] bytes, int off, int len) throws ErrnoException;

	public static native void close(int fd) throws ErrnoException;

	public static native void setBlocking(int fd, boolean blocking) throws ErrnoException;

	public static native void setsockoptInt(int fd, int level, int option, int value)
	    throws ErrnoException;

	public static native long sysconf(int name);

	/** { st_mode, st_size, st_mtime }. */
	public static native long[] fstat(int fd) throws ErrnoException;
}
