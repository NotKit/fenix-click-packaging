package android.icu.text;

import java.util.Collection;
import java.util.Locale;

/**
 * Joins a list the way CLDR's listPattern does.
 *
 * Approximate, and English-only in its wording: JDK 21 has no list formatter
 * (java.text.ListFormat arrived in JDK 22) and no CLDR listPattern data is
 * reachable from here, so the conjunctions below are hardcoded English and the
 * separator is always ", ". A locale whose list pattern differs -- Spanish
 * "y"/"e", Chinese with no space, Arabic "و" -- gets the English shape with an
 * English word in it. NARROW needs no conjunction at all, so that width is
 * right for every locale that separates its lists with a comma.
 */
public class ListFormatter {
	/** Which conjunction the list uses. */
	public enum Type { AND, OR, UNITS }

	/** How much room the conjunction gets. */
	public enum Width { WIDE, SHORT, NARROW }

	private final Type type;
	private final Width width;

	private ListFormatter(Type type, Width width) {
		this.type = type;
		this.width = width;
	}

	public static ListFormatter getInstance(Locale locale) {
		return getInstance(locale, Type.AND, Width.WIDE);
	}

	public static ListFormatter getInstance() {
		return getInstance(Locale.getDefault());
	}

	/** The locale is accepted and ignored; see the class javadoc. */
	public static ListFormatter getInstance(Locale locale, Type type, Width width) {
		return new ListFormatter(type == null ? Type.AND : type, width == null ? Width.WIDE : width);
	}

	public String format(Collection<?> items) {
		if (items == null || items.isEmpty())
			return "";
		Object[] values = items.toArray();
		if (values.length == 1)
			return String.valueOf(values[0]);

		String last = lastSeparator();
		StringBuilder out = new StringBuilder();
		for (int i = 0; i < values.length; i++) {
			if (i > 0)
				out.append(i == values.length - 1 ? last : ", ");
			out.append(values[i]);
		}
		return out.toString();
	}

	/** What goes before the last item, comma included where CLDR (en) has one. */
	private String lastSeparator() {
		if (width == Width.NARROW || type == Type.UNITS)
			return ", ";
		if (type == Type.OR)
			return ", or ";
		return width == Width.SHORT ? ", & " : ", and ";
	}

	@Override
	public String toString() {
		return "ListFormatter[" + type + "," + width + "]";
	}
}
