package android.system;

/** Only the three fields api-impl reads; the real struct has a dozen more. */
public final class StructStat {
	public final int st_mode;
	public final long st_size;
	/** Seconds since the epoch, as stat(2) reports it. */
	public final long st_mtime;

	public StructStat(int st_mode, long st_size, long st_mtime) {
		this.st_mode = st_mode;
		this.st_size = st_size;
		this.st_mtime = st_mtime;
	}
}
