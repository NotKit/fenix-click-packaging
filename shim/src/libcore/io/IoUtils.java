package libcore.io;

import android.system.ErrnoException;

import java.io.FileDescriptor;
import java.io.FileOutputStream;

public final class IoUtils {
	private IoUtils() {}

	public static void closeQuietly(AutoCloseable closeable) {
		if (closeable == null)
			return;
		try {
			closeable.close();
		} catch (Exception ignored) {
		}
	}

	public static void closeQuietly(FileDescriptor fd) {
		if (fd == null || !fd.valid())
			return;
		try {
			if (Posix.isAvailable())
				Posix.close(Posix.fdOf(fd));
			else
				new FileOutputStream(fd).close(); // closes the descriptor it wraps
		} catch (Exception ignored) {
		}
	}

	public static void setBlocking(FileDescriptor fd, boolean blocking) throws ErrnoException {
		Posix.require("fcntl");
		Posix.setBlocking(Posix.fdOf(fd), blocking);
	}
}
