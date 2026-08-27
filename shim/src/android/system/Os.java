package android.system;

import libcore.io.Posix;

import java.io.FileDescriptor;
import java.io.IOException;
import java.nio.file.FileStore;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.PosixFileAttributes;
import java.nio.file.attribute.PosixFilePermission;

/**
 * The POSIX calls api-impl makes. stat/statvfs go through NIO, which knows the
 * same things; everything that needs a raw descriptor goes through
 * {@link Posix} and so needs libportshim.so.
 */
public final class Os {
	private Os() {}

	public static StructStat stat(String path) throws ErrnoException {
		return stat(Paths.get(path), true);
	}

	public static StructStat lstat(String path) throws ErrnoException {
		return stat(Paths.get(path), false);
	}

	private static StructStat stat(Path path, boolean followLinks) throws ErrnoException {
		try {
			LinkOption[] options = followLinks ? new LinkOption[0]
			                                   : new LinkOption[] {LinkOption.NOFOLLOW_LINKS};
			PosixFileAttributes attrs = Files.readAttributes(path, PosixFileAttributes.class, options);
			return new StructStat(modeOf(attrs), attrs.size(), attrs.lastModifiedTime().toMillis() / 1000);
		} catch (IOException e) {
			throw new ErrnoException("stat", errnoFor(e), e);
		}
	}

	public static StructStatVfs statvfs(String path) throws ErrnoException {
		try {
			FileStore store = Files.getFileStore(Paths.get(path));
			long blockSize = store.getBlockSize();
			if (blockSize <= 0)
				blockSize = 4096;
			return new StructStatVfs(store.getTotalSpace() / blockSize,
			    store.getUnallocatedSpace() / blockSize, store.getUsableSpace() / blockSize,
			    blockSize, blockSize);
		} catch (IOException e) {
			throw new ErrnoException("statvfs", errnoFor(e), e);
		}
	}

	public static StructStat fstat(FileDescriptor fd) throws ErrnoException {
		Posix.require("fstat");
		long[] st = Posix.fstat(Posix.fdOf(fd));
		return new StructStat((int)st[0], st[1], st[2]);
	}

	public static FileDescriptor open(String path, int flags, int mode) throws ErrnoException {
		Posix.require("open");
		return Posix.fdFor(Posix.open(path, flags, mode));
	}

	public static FileDescriptor dup(FileDescriptor fd) throws ErrnoException {
		Posix.require("dup");
		return Posix.fdFor(Posix.dup(Posix.fdOf(fd)));
	}

	public static FileDescriptor[] pipe() throws ErrnoException {
		Posix.require("pipe");
		int[] fds = Posix.pipe();
		return new FileDescriptor[] {Posix.fdFor(fds[0]), Posix.fdFor(fds[1])};
	}

	public static void socketpair(int domain, int type, int protocol, FileDescriptor fd1,
	    FileDescriptor fd2) throws ErrnoException {
		Posix.require("socketpair");
		int[] fds = Posix.socketpair(domain, type, protocol);
		Posix.setFd(fd1, fds[0]);
		Posix.setFd(fd2, fds[1]);
	}

	public static long lseek(FileDescriptor fd, long offset, int whence) throws ErrnoException {
		Posix.require("lseek");
		return Posix.lseek(Posix.fdOf(fd), offset, whence);
	}

	public static int read(FileDescriptor fd, byte[] bytes, int byteOffset, int byteCount)
	    throws ErrnoException {
		Posix.require("read");
		return Posix.read(Posix.fdOf(fd), bytes, byteOffset, byteCount);
	}

	public static int write(FileDescriptor fd, byte[] bytes, int byteOffset, int byteCount)
	    throws ErrnoException {
		Posix.require("write");
		return Posix.write(Posix.fdOf(fd), bytes, byteOffset, byteCount);
	}

	public static void close(FileDescriptor fd) throws ErrnoException {
		Posix.require("close");
		Posix.close(Posix.fdOf(fd));
	}

	public static void setsockoptInt(FileDescriptor fd, int level, int option, int value)
	    throws ErrnoException {
		Posix.require("setsockopt");
		Posix.setsockoptInt(Posix.fdOf(fd), level, option, value);
	}

	/**
	 * The values are glibc's, not bionic's (see {@link OsConstants}). Without
	 * libportshim.so the two names Fenix asks for still answer, from the JVM.
	 */
	public static long sysconf(int name) {
		if (Posix.isAvailable())
			return Posix.sysconf(name);
		if (name == OsConstants._SC_NPROCESSORS_CONF)
			return Runtime.getRuntime().availableProcessors();
		if (name == OsConstants._SC_CLK_TCK)
			return 100; // CONFIG_HZ on every Linux/x86_64 distro kernel
		return -1;
	}

	private static int modeOf(PosixFileAttributes attrs) {
		int mode = 0;
		if (attrs.isSymbolicLink())
			mode |= OsConstants.S_IFLNK;
		else if (attrs.isDirectory())
			mode |= OsConstants.S_IFDIR;
		else if (attrs.isRegularFile())
			mode |= OsConstants.S_IFREG;

		for (PosixFilePermission p : attrs.permissions()) {
			switch (p) {
			case OWNER_READ: mode |= OsConstants.S_IRUSR; break;
			case OWNER_WRITE: mode |= OsConstants.S_IWUSR; break;
			case OWNER_EXECUTE: mode |= OsConstants.S_IXUSR; break;
			case GROUP_READ: mode |= OsConstants.S_IRGRP; break;
			case GROUP_WRITE: mode |= OsConstants.S_IWGRP; break;
			case GROUP_EXECUTE: mode |= OsConstants.S_IXGRP; break;
			case OTHERS_READ: mode |= OsConstants.S_IROTH; break;
			case OTHERS_WRITE: mode |= OsConstants.S_IWOTH; break;
			case OTHERS_EXECUTE: mode |= OsConstants.S_IXOTH; break;
			}
		}
		return mode;
	}

	/** Callers only ever compare against ENOENT, so the rest collapse to EIO. */
	private static int errnoFor(IOException e) {
		return e instanceof java.nio.file.NoSuchFileException ? 2 /* ENOENT */ : 5 /* EIO */;
	}
}
