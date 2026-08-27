package android.icu.util;

import java.util.Date;

/**
 * ICU's TimeZone over {@link java.util.TimeZone}.
 *
 * The zone rules are the JDK's tzdb, which is the same IANA data ICU carries,
 * so offsets agree. What is not here is ICU's own additions: the ICU/JDK zone
 * type switch, {@code getDisplayName} with an ICU style, and the ICU-only
 * "unknown zone" (a bad id gives GMT, as java.util.TimeZone does).
 */
public class TimeZone {
	/**
	 * ICU's frozen GMT zone. AOSP's is a {@code ConstantZone} with id
	 * "Etc/GMT" and offset 0 (read out of a real ART libcore: see NOTES.md);
	 * this is the JDK's zone of the same name, which is the same rule.
	 * androidx.compose.material3's CalendarModel hands it to
	 * {@code DateFormat.setTimeZone} so a date picker's UTC millis format as
	 * the day the user picked and not the day in the host's zone.
	 */
	public static final TimeZone GMT_ZONE =
	    new TimeZone(java.util.TimeZone.getTimeZone("Etc/GMT"));

	private final java.util.TimeZone zone;

	protected TimeZone(java.util.TimeZone zone) {
		this.zone = zone;
	}

	public static TimeZone getDefault() {
		return new TimeZone(java.util.TimeZone.getDefault());
	}

	public static TimeZone getTimeZone(String id) {
		return new TimeZone(java.util.TimeZone.getTimeZone(id));
	}

	public static String[] getAvailableIDs() {
		return java.util.TimeZone.getAvailableIDs();
	}

	public String getID() {
		return zone.getID();
	}

	/** Total offset from UTC in milliseconds at the given instant, DST included. */
	public int getOffset(long date) {
		return zone.getOffset(date);
	}

	public int getRawOffset() {
		return zone.getRawOffset();
	}

	public boolean inDaylightTime(Date date) {
		return zone.inDaylightTime(date);
	}

	public boolean useDaylightTime() {
		return zone.useDaylightTime();
	}

	/** The JDK zone behind this one, so the shim's formatters can use it. */
	public java.util.TimeZone toJavaTimeZone() {
		return zone;
	}

	@Override
	public String toString() {
		return "android.icu.util.TimeZone[" + zone.getID() + "]";
	}
}
