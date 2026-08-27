package android.icu.text;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * The skeleton-driven date formatter material design's date picker asks ICU for.
 *
 * Approximate on two counts. The skeleton is turned into a pattern by
 * {@link libcore.icu.ICU#getBestDateTimePattern}, which assembles one from the
 * locale's own short date/time formats instead of from CLDR's availableFormats
 * -- field order, separators and the hour cycle follow the locale, wording like
 * "d 'de' MMMM" does not. And {@link #setContext} is recorded but not acted on:
 * java.text.SimpleDateFormat has no capitalization control, so a standalone
 * month keeps the JDK's formatting case.
 */
public class DateFormat {
	private final SimpleDateFormat format;
	private DisplayContext context = DisplayContext.CAPITALIZATION_NONE;

	protected DateFormat(SimpleDateFormat format) {
		this.format = format;
	}

	public static DateFormat getInstanceForSkeleton(String skeleton, Locale locale) {
		if (locale == null)
			locale = Locale.getDefault();
		String pattern = libcore.icu.ICU.getBestDateTimePattern(skeleton, locale);
		return new DateFormat(new SimpleDateFormat(pattern, locale));
	}

	public static DateFormat getInstanceForSkeleton(String skeleton) {
		return getInstanceForSkeleton(skeleton, Locale.getDefault());
	}

	public void setTimeZone(android.icu.util.TimeZone zone) {
		if (zone != null)
			format.setTimeZone(zone.toJavaTimeZone());
	}

	public android.icu.util.TimeZone getTimeZone() {
		return android.icu.util.TimeZone.getTimeZone(format.getTimeZone().getID());
	}

	/** Recorded so {@link #getContext} answers; nothing reads it. See the class javadoc. */
	public void setContext(DisplayContext context) {
		this.context = context;
	}

	public DisplayContext getContext(Object type) {
		return context;
	}

	public String format(Date date) {
		return format.format(date);
	}

	public String toPattern() {
		return format.toPattern();
	}
}
