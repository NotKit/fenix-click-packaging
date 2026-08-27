package libcore.icu;

import java.text.DateFormatSymbols;
import java.time.DayOfWeek;
import java.time.Month;
import java.time.format.TextStyle;
import java.util.Calendar;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * The month/weekday/am-pm names android.text.format.DateFormat formats with.
 *
 * Month arrays are indexed like Calendar.JANUARY (0-based), weekday arrays like
 * Calendar.SUNDAY (1-based, entry 0 unused) — the same layout libcore uses, so
 * api-impl's indexing is unchanged. Names come from java.text.DateFormatSymbols
 * and java.time's stand-alone forms.
 */
public final class LocaleData {
	private static final Map<Locale, LocaleData> CACHE = new HashMap<>();

	public String[] amPm;

	public String[] longMonthNames;
	public String[] shortMonthNames;
	public String[] tinyMonthNames;
	public String[] longStandAloneMonthNames;
	public String[] shortStandAloneMonthNames;
	public String[] tinyStandAloneMonthNames;

	public String[] longWeekdayNames;
	public String[] shortWeekdayNames;
	public String[] tinyWeekdayNames;
	public String[] longStandAloneWeekdayNames;
	public String[] shortStandAloneWeekdayNames;
	public String[] tinyStandAloneWeekdayNames;

	public static synchronized LocaleData get(Locale locale) {
		if (locale == null)
			locale = Locale.getDefault();
		LocaleData data = CACHE.get(locale);
		if (data == null) {
			data = new LocaleData(locale);
			CACHE.put(locale, data);
		}
		return data;
	}

	private LocaleData(Locale locale) {
		DateFormatSymbols symbols = DateFormatSymbols.getInstance(locale);

		amPm = symbols.getAmPmStrings();

		longMonthNames = symbols.getMonths();
		shortMonthNames = symbols.getShortMonths();
		tinyMonthNames = firstLetters(shortMonthNames);
		longStandAloneMonthNames = standAloneMonths(locale, TextStyle.FULL_STANDALONE);
		shortStandAloneMonthNames = standAloneMonths(locale, TextStyle.SHORT_STANDALONE);
		tinyStandAloneMonthNames = standAloneMonths(locale, TextStyle.NARROW_STANDALONE);

		longWeekdayNames = symbols.getWeekdays();
		shortWeekdayNames = symbols.getShortWeekdays();
		tinyWeekdayNames = firstLetters(shortWeekdayNames);
		longStandAloneWeekdayNames = standAloneWeekdays(locale, TextStyle.FULL_STANDALONE);
		shortStandAloneWeekdayNames = standAloneWeekdays(locale, TextStyle.SHORT_STANDALONE);
		tinyStandAloneWeekdayNames = standAloneWeekdays(locale, TextStyle.NARROW_STANDALONE);
	}

	private static String[] standAloneMonths(Locale locale, TextStyle style) {
		String[] names = new String[13];
		for (int i = Calendar.JANUARY; i <= Calendar.DECEMBER; i++)
			names[i] = Month.of(i + 1).getDisplayName(style, locale);
		names[12] = "";
		return names;
	}

	private static String[] standAloneWeekdays(Locale locale, TextStyle style) {
		String[] names = new String[8];
		names[0] = "";
		for (int day = Calendar.SUNDAY; day <= Calendar.SATURDAY; day++)
			names[day] = DayOfWeek.of((day + 5) % 7 + 1).getDisplayName(style, locale);
		return names;
	}

	private static String[] firstLetters(String[] names) {
		String[] tiny = new String[names.length];
		for (int i = 0; i < names.length; i++) {
			String name = names[i];
			tiny[i] = name == null || name.isEmpty() ? "" : name.substring(0, name.offsetByCodePoints(0, 1));
		}
		return tiny;
	}
}
