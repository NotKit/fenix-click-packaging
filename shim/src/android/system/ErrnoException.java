package android.system;

import java.io.IOException;

public final class ErrnoException extends Exception {
	private final String functionName;
	public final int errno;

	public ErrnoException(String functionName, int errno) {
		this.functionName = functionName;
		this.errno = errno;
	}

	public ErrnoException(String functionName, int errno, Throwable cause) {
		super(cause);
		this.functionName = functionName;
		this.errno = errno;
	}

	@Override
	public String getMessage() {
		return functionName + " failed: errno " + errno;
	}

	public IOException rethrowAsIOException() throws IOException {
		throw new IOException(getMessage(), this);
	}
}
