package android.system;

/** Linux/x86_64 values for the constants api-impl and Fenix read. */
public final class OsConstants {
	private OsConstants() {}

	public static final int AF_UNIX = 1;
	public static final int SOCK_STREAM = 1;
	public static final int SOCK_SEQPACKET = 5;

	public static final int SOL_SOCKET = 1;
	public static final int SO_PASSCRED = 16;

	public static final int EACCES = 13;
	public static final int EAGAIN = 11;

	// glibc's sysconf numbering (bits/confname.h), not bionic's -- Os.sysconf
	// hands these straight to the host libc through libportshim.so, and the two
	// libcs number _SC_* differently.
	public static final int _SC_CLK_TCK = 2;
	public static final int _SC_NPROCESSORS_CONF = 83;

	public static final int O_RDONLY = 0;
	public static final int O_WRONLY = 1;
	public static final int O_RDWR = 2;
	public static final int O_CREAT = 0100;
	public static final int O_TRUNC = 01000;
	public static final int O_APPEND = 02000;
	public static final int O_NONBLOCK = 04000;
	public static final int O_CLOEXEC = 02000000;

	public static final int SEEK_SET = 0;
	public static final int SEEK_CUR = 1;
	public static final int SEEK_END = 2;

	public static final int S_IFMT = 0170000;
	public static final int S_IFDIR = 0040000;
	public static final int S_IFREG = 0100000;
	public static final int S_IFLNK = 0120000;

	public static final int S_IRWXU = 0700;
	public static final int S_IRUSR = 0400;
	public static final int S_IWUSR = 0200;
	public static final int S_IXUSR = 0100;
	public static final int S_IRWXG = 070;
	public static final int S_IRGRP = 040;
	public static final int S_IWGRP = 020;
	public static final int S_IXGRP = 010;
	public static final int S_IRWXO = 07;
	public static final int S_IROTH = 04;
	public static final int S_IWOTH = 02;
	public static final int S_IXOTH = 01;

	public static boolean S_ISDIR(int mode) {
		return (mode & S_IFMT) == S_IFDIR;
	}

	public static boolean S_ISREG(int mode) {
		return (mode & S_IFMT) == S_IFREG;
	}

	public static boolean S_ISLNK(int mode) {
		return (mode & S_IFMT) == S_IFLNK;
	}
}
