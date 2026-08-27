package android.icu.text;

import java.util.Locale;

/**
 * "in 5 minutes" / "5 minutes ago", which LocaleController asks ICU for.
 *
 * Approximate: the JDK carries no relative-time patterns, so the wording is
 * English regardless of locale. Only the units and directions the app uses are
 * defined. A locale-aware version means either bundling CLDR data or using the
 * framework's own strings, neither of which belongs in the shim.
 */
public final class RelativeDateTimeFormatter {
	public enum Direction { LAST, NEXT, THIS, PLAIN }

	public enum RelativeUnit { SECONDS, MINUTES, HOURS, DAYS, WEEKS, MONTHS, QUARTERS, YEARS }

	private RelativeDateTimeFormatter() {}

	public static RelativeDateTimeFormatter getInstance() {
		return new RelativeDateTimeFormatter();
	}

	public static RelativeDateTimeFormatter getInstance(Locale locale) {
		return new RelativeDateTimeFormatter();
	}

	public String format(double quantity, Direction direction, RelativeUnit unit) {
		String amount = quantity == Math.rint(quantity) ? String.valueOf((long)quantity)
		                                                : String.valueOf(quantity);
		String name = unit.name().toLowerCase(Locale.ROOT);
		if (quantity == 1)
			name = name.substring(0, name.length() - 1); // "minutes" -> "minute"

		switch (direction) {
		case NEXT:
			return "in " + amount + " " + name;
		case LAST:
			return amount + " " + name + " ago";
		default:
			return amount + " " + name;
		}
	}
}
