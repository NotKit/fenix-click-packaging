package android.icu.text;

import java.util.Locale;

/**
 * The digit symbols Compose asks ICU for, over {@link java.text.DecimalFormatSymbols}.
 *
 * Approximate: the JDK's symbols come from its own CLDR copy, so the zero digit
 * and the digit strings follow the locale's numbering system as the JDK knows
 * it. Numbering systems the JDK does not carry (and ICU's per-digit string
 * table, which can hold surrogate pairs) collapse to the ten code points
 * starting at the zero digit.
 */
public class DecimalFormatSymbols {
	private final java.text.DecimalFormatSymbols symbols;

	private DecimalFormatSymbols(java.text.DecimalFormatSymbols symbols) {
		this.symbols = symbols;
	}

	public static DecimalFormatSymbols getInstance(Locale locale) {
		return new DecimalFormatSymbols(
		    java.text.DecimalFormatSymbols.getInstance(locale == null ? Locale.getDefault() : locale));
	}

	public static DecimalFormatSymbols getInstance() {
		return getInstance(Locale.getDefault());
	}

	public char getZeroDigit() {
		return symbols.getZeroDigit();
	}

	/**
	 * The ten digit strings, 0 through 9. ICU keeps a real table because a
	 * numbering system may need surrogate pairs; here they are derived from the
	 * zero digit, which is right for every BMP-contiguous numbering system.
	 */
	public String[] getDigitStrings() {
		char zero = symbols.getZeroDigit();
		String[] digits = new String[10];
		for (int i = 0; i < 10; i++)
			digits[i] = String.valueOf((char)(zero + i));
		return digits;
	}

	public char getDecimalSeparator() {
		return symbols.getDecimalSeparator();
	}

	public char getGroupingSeparator() {
		return symbols.getGroupingSeparator();
	}
}
