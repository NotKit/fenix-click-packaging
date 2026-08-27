package android.system;

/** The block counts android.os.StatFs reports. */
public final class StructStatVfs {
	public final long f_blocks;
	public final long f_bfree;
	public final long f_bavail;
	public final long f_frsize;
	public final long f_bsize;

	public StructStatVfs(long f_blocks, long f_bfree, long f_bavail, long f_frsize, long f_bsize) {
		this.f_blocks = f_blocks;
		this.f_bfree = f_bfree;
		this.f_bavail = f_bavail;
		this.f_frsize = f_frsize;
		this.f_bsize = f_bsize;
	}
}
