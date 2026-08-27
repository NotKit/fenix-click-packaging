package libcore.io;

/**
 * libcore's POSIX facade. Only the calls api-impl makes through
 * {@link Libcore#os} are declared; the real interface has about a hundred.
 */
public interface Os {
	int getpid();

	int getppid();

	int gettid();
}
