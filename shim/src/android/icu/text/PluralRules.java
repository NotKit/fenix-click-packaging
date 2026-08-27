package android.icu.text;

import java.util.Locale;

/**
 * Picks the plural keyword Resources.getQuantityString() looks up.
 *
 * Approximate: instead of CLDR's rule set this implements the default
 * one/other rule plus the Slavic one/few/many family. Telegram formats its own
 * plurals through LocaleController, so this only backs framework resources.
 */
public class PluralRules {
	public static final String KEYWORD_ZERO = "zero";
	public static final String KEYWORD_ONE = "one";
	public static final String KEYWORD_TWO = "two";
	public static final String KEYWORD_FEW = "few";
	public static final String KEYWORD_MANY = "many";
	public static final String KEYWORD_OTHER = "other";

	private final boolean slavic;

	private PluralRules(boolean slavic) {
		this.slavic = slavic;
	}

	public static PluralRules forLocale(Locale locale) {
		String language = locale == null ? "" : locale.getLanguage();
		return new PluralRules(
		    language.equals("ru") || language.equals("uk") || language.equals("be")
		    || language.equals("sr") || language.equals("hr") || language.equals("bs"));
	}

	public String select(double number) {
		if (number != Math.rint(number))
			return KEYWORD_OTHER;
		long n = Math.abs((long)number);

		if (!slavic)
			return n == 1 ? KEYWORD_ONE : KEYWORD_OTHER;

		long mod10 = n % 10;
		long mod100 = n % 100;
		if (mod10 == 1 && mod100 != 11)
			return KEYWORD_ONE;
		if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
			return KEYWORD_FEW;
		return KEYWORD_MANY;
	}
}
