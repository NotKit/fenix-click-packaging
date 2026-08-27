package libcore.icu;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * The two ICU4C entry points android.text.format.DateFormat uses.
 *
 * Approximate: the JDK has no skeleton-to-pattern service, so
 * {@link #getBestDateTimePattern} has to answer out of what a JDK does have.
 * Two paths, and they are approximate in different degrees:
 *
 * - a skeleton asking for a month *name* is answered from the locale's own
 *   medium or long date format, which is CLDR's own yMMMd/yMMMMd in nearly
 *   every locale, with the fields the skeleton did not ask for deleted. That
 *   keeps CLDR's wording -- "MMM d, y", "d 'de' MMMM 'de' y", "y年M月d日" --
 *   and it is checked before use (see faithful()), falling back to synthesis
 *   when the locale's pattern does not fit.
 * - anything else is synthesised from the locale's short date/time formats.
 *   Field order, separators and the hour cycle follow the locale; CLDR's
 *   availableFormats widths and wording do not.
 *
 * Known to differ from real ICU either way: the weekday is always joined as
 * "E, date", where CLDR puts it in parentheses after the date in ja and zh.
 */
public final class ICU {
	private ICU() {}

	public static String getBestDateTimePattern(String skeleton, Locale locale) {
		if (skeleton == null || skeleton.isEmpty())
			return skeleton;
		if (locale == null)
			locale = Locale.getDefault();

		StringBuilder date = new StringBuilder();
		StringBuilder time = new StringBuilder();
		boolean hour12 = isHour12(locale);
		String weekday = count(skeleton, 'E') > 0 ? repeat('E', count(skeleton, 'E')) : null;
		String datePattern = datePattern(locale);
		boolean previousTextual = false;

		// a month *name* asks for CLDR wording no synthesis can invent, and the
		// locale's own medium/long date format is that wording -- use it when it
		// fits the skeleton, and fall through to synthesis when it does not.
		String fromLocale = textualDatePattern(skeleton, locale);
		if (fromLocale != null)
			date.append(fromLocale);

		// the locale decides the order of the date fields, the skeleton which ones appear
		for (char field : date.length() > 0 ? new char[0] : getDateFormatOrder(datePattern)) {
			char asked = count(skeleton, field) > 0 ? field
			    : (field == 'M' && count(skeleton, 'L') > 0 ? 'L' : 0);
			if (asked == 0)
				continue;
			boolean textual = isTextual(skeleton, asked);
			// firefox-atl deviation from linux-port/shim: a space wins if *either*
			// side is a name, so "MMMd" is "MMM d" and not "MMM/d". CLDR never
			// punctuates between a month name and a number.
			if (date.length() > 0)
				date.append(textual || previousTextual ? " " : separator(datePattern));
			date.append(repeat(asked, count(skeleton, asked)));
			previousTextual = textual;
		}

		if (count(skeleton, 'j') + count(skeleton, 'H') + count(skeleton, 'h') > 0) {
			boolean twelve = count(skeleton, 'h') > 0 || (count(skeleton, 'j') > 0 && hour12);
			// CLDR pads the hour only in the 24-hour cycle, and always pads minutes
			// and seconds, whatever width the skeleton asked for
			time.append(twelve ? "h" : "HH");
			if (count(skeleton, 'm') > 0)
				time.append(":mm");
			if (count(skeleton, 's') > 0)
				time.append(":ss");
			if (twelve)
				time.append(" a");
		}

		StringBuilder out = new StringBuilder();
		if (weekday != null)
			out.append(weekday);
		if (date.length() > 0)
			out.append(out.length() > 0 ? ", " : "").append(date);
		if (time.length() > 0)
			out.append(out.length() > 0 ? " " : "").append(time);
		return out.length() > 0 ? out.toString() : skeleton;
	}

	/**
	 * The order of the day, month and year fields in a numeric date pattern, as
	 * a three-character array of 'd', 'M' and 'y'.
	 */
	public static char[] getDateFormatOrder(String pattern) {
		char[] result = new char[3];
		int at = 0;
		boolean quoted = false;
		for (int i = 0; i < pattern.length() && at < 3; i++) {
			char c = pattern.charAt(i);
			if (c == '\'') {
				quoted = !quoted;
				continue;
			}
			if (quoted)
				continue;
			char field = normalise(c);
			if (field != 'd' && field != 'M' && field != 'y')
				continue;
			if (!contains(result, at, field))
				result[at++] = field;
		}
		return result;
	}

	private static boolean contains(char[] array, int length, char c) {
		for (int i = 0; i < length; i++) {
			if (array[i] == c)
				return true;
		}
		return false;
	}

	/** 'L' (stand-alone month) counts as a month, 'Y' (week year) as a year. */
	private static char normalise(char c) {
		if (c == 'L')
			return 'M';
		if (c == 'Y')
			return 'y';
		return c;
	}

	private static boolean isHour12(Locale locale) {
		String pattern = timePattern(locale);
		return pattern.indexOf('h') >= 0 || pattern.indexOf('K') >= 0;
	}

	private static String datePattern(Locale locale) {
		java.text.DateFormat format = java.text.DateFormat.getDateInstance(java.text.DateFormat.SHORT, locale);
		return format instanceof SimpleDateFormat ? ((SimpleDateFormat)format).toPattern() : "M/d/yy";
	}

	private static String timePattern(Locale locale) {
		java.text.DateFormat format = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT, locale);
		return format instanceof SimpleDateFormat ? ((SimpleDateFormat)format).toPattern() : "h:mm a";
	}

	/** The punctuation the locale puts between numeric date fields. */
	private static String separator(String pattern) {
		for (int i = 0; i < pattern.length(); i++) {
			char c = pattern.charAt(i);
			if (c == '.' || c == '/' || c == '-')
				return String.valueOf(c);
		}
		return " ";
	}

	/**
	 * The date half of a skeleton that asks for a month *name*, copied out of the
	 * locale's own medium/long date format rather than synthesised.
	 *
	 * CLDR's medium date format is its `yMMMd` and its long one its `yMMMMd` in
	 * nearly every locale -- exactly what these skeletons ask for -- so taking
	 * that pattern and deleting the fields the skeleton did not ask for keeps the
	 * wording a synthesised pattern cannot invent ("d 'de' MMMM", "y年M月d日",
	 * "MMM d, y"). Returns null when the locale's own pattern is numeric or the
	 * result would not be a faithful answer, and the caller synthesises instead.
	 */
	private static String textualDatePattern(String skeleton, Locale locale) {
		int monthWidth = Math.max(count(skeleton, 'M'), count(skeleton, 'L'));
		if (monthWidth < 3)
			return null;
		boolean wantYear = count(skeleton, 'y') + count(skeleton, 'Y') > 0;
		boolean wantDay = count(skeleton, 'd') > 0;
		char monthField = count(skeleton, 'L') >= 3 ? 'L' : 'M';

		String source = localePattern(locale, monthWidth >= 4
		    ? java.text.DateFormat.LONG : java.text.DateFormat.MEDIUM);
		if (!usableSource(source))
			source = localePattern(locale, java.text.DateFormat.LONG);
		if (!usableSource(source))
			return null;
		// "y年M月d日" has no MMM and needs none: the month is spelled by the
		// literal after it, so keep the pattern's own width.
		if (!hasTextualMonth(source))
			monthWidth = -1;

		List<String> tokens = tokenise(source);
		boolean[] drop = new boolean[tokens.size()];
		boolean anyKept = false;
		for (int i = 0; i < tokens.size(); i++) {
			char field = fieldOf(tokens.get(i));
			if (field == 0)
				continue;
			boolean keep = field == 'M' || field == 'L' ? true
			    : field == 'y' || field == 'u' || field == 'Y' ? wantYear
			    : field == 'd' ? wantDay : false;
			drop[i] = !keep;
			anyKept |= keep;
		}
		if (!anyKept)
			return null;
		// a dropped field takes the punctuation *and* wording that follows it:
		// "MMMM d, y" without the day is "MMMM y" and not "MMMM, y", and
		// "d MMMM y 'г'." without the year is "d MMMM".
		for (int i = 0; i < tokens.size(); i++) {
			if (!drop[i] || fieldOf(tokens.get(i)) == 0)
				continue;
			if (i + 1 < tokens.size() && fieldOf(tokens.get(i + 1)) == 0)
				drop[i + 1] = true;
			else if (i > 0 && fieldOf(tokens.get(i - 1)) == 0)
				drop[i - 1] = true;   // a dropped last field takes what led up to it
		}
		// then trim punctuation left dangling at either end -- but not a word,
		// which belongs to the field beside it ("y年M月d日" keeps its 日).
		for (int i = tokens.size() - 1; i >= 0 && (drop[i] || isPunctuation(tokens.get(i))); i--)
			drop[i] = true;
		for (int i = 0; i < tokens.size() && (drop[i] || isPunctuation(tokens.get(i))); i++)
			drop[i] = true;

		StringBuilder out = new StringBuilder();
		for (int i = 0; i < tokens.size(); i++) {
			if (drop[i])
				continue;
			char field = fieldOf(tokens.get(i));
			out.append((field == 'M' || field == 'L') && monthWidth > 0
			    ? repeat(monthField, monthWidth) : tokens.get(i));
		}
		String result = out.toString().trim();
		return faithful(result, wantYear, wantDay) ? result : null;
	}

	/** One run per element: a repeated field letter, or a literal (quotes kept). */
	private static List<String> tokenise(String pattern) {
		List<String> tokens = new ArrayList<>();
		int i = 0;
		while (i < pattern.length()) {
			char c = pattern.charAt(i);
			if (isFieldLetter(c)) {
				int j = i;
				while (j < pattern.length() && pattern.charAt(j) == c)
					j++;
				tokens.add(pattern.substring(i, j));
				i = j;
			} else {
				int j = i;
				while (j < pattern.length() && !isFieldLetter(pattern.charAt(j))) {
					if (pattern.charAt(j) == '\'') {         // a quoted literal, letters and all
						int end = pattern.indexOf('\'', j + 1);
						j = end < 0 ? pattern.length() : end + 1;
					} else {
						j++;
					}
				}
				tokens.add(pattern.substring(i, j));
				i = j;
			}
		}
		return tokens;
	}

	private static boolean isFieldLetter(char c) {
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
	}

	/** The field letter a token is a run of, or 0 for a literal. */
	private static char fieldOf(String token) {
		return token.isEmpty() || !isFieldLetter(token.charAt(0)) ? 0 : token.charAt(0);
	}

	/** A literal token with no letters in it: separators, spaces, RTL marks. */
	private static boolean isPunctuation(String token) {
		if (fieldOf(token) != 0)
			return false;
		for (int i = 0; i < token.length(); i++) {
			if (Character.isLetter(token.charAt(i)))
				return false;
		}
		return true;
	}

	private static boolean hasTextualMonth(String pattern) {
		return pattern.contains("MMM") || pattern.contains("LLL");
	}

	/**
	 * Whether a locale's date pattern spells its fields out rather than joining
	 * them with punctuation: a month name, or a word literal beside the numbers
	 * as CJK's 年月日 are. ("dd‏/MM‏/y" does not count -- those are RTL marks.)
	 */
	private static boolean usableSource(String pattern) {
		if (hasTextualMonth(pattern))
			return true;
		for (String token : tokenise(pattern)) {
			if (fieldOf(token) != 0)
				continue;
			for (int i = 0; i < token.length(); i++) {
				char c = token.charAt(i);
				if (c != '\'' && Character.isLetter(c) && !isFieldLetter(c))
					return true;
			}
		}
		return false;
	}

	/**
	 * The filtered pattern must hold exactly the fields asked for, once each, and
	 * still be a pattern both java.text and java.time accept -- Fenix's own
	 * IsoPromoDeadline feeds the answer to DateTimeFormatter.ofPattern.
	 */
	private static boolean faithful(String pattern, boolean wantYear, boolean wantDay) {
		if (pattern.isEmpty())
			return false;
		int month = 0, year = 0, day = 0, other = 0;
		for (String token : tokenise(pattern)) {
			switch (fieldOf(token)) {
			case 0: break;
			case 'M': case 'L': month++; break;
			case 'y': case 'u': case 'Y': year++; break;
			case 'd': day++; break;
			default: other++; break;
			}
		}
		if (month != 1 || other != 0 || year != (wantYear ? 1 : 0) || day != (wantDay ? 1 : 0))
			return false;
		try {
			new SimpleDateFormat(pattern, Locale.US);
			java.time.format.DateTimeFormatter.ofPattern(pattern);
		} catch (RuntimeException e) {
			return false;
		}
		return true;
	}

	private static String localePattern(Locale locale, int style) {
		java.text.DateFormat format = java.text.DateFormat.getDateInstance(style, locale);
		return format instanceof SimpleDateFormat ? ((SimpleDateFormat)format).toPattern() : "";
	}

	private static boolean isTextual(String skeleton, char field) {
		return (field == 'M' || field == 'L') && count(skeleton, field) >= 3;
	}

	private static int count(String skeleton, char field) {
		int n = 0;
		for (int i = 0; i < skeleton.length(); i++) {
			if (skeleton.charAt(i) == field)
				n++;
		}
		return n;
	}

	private static String repeat(char c, int n) {
		return String.valueOf(c).repeat(n);
	}
}
