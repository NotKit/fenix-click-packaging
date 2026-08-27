package android.icu.util;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Just enough of ICU4J's locale for android.os.LocaleList's script matching.
 *
 * Approximate: {@link #addLikelySubtags} has no CLDR likely-subtags table, so it
 * fills in the script from a short list of languages whose default script is not
 * Latin, and leaves everything else as-is.
 */
public class ULocale {
	private static final Map<String, String> LIKELY_SCRIPTS = new HashMap<>();

	static {
		LIKELY_SCRIPTS.put("ru", "Cyrl");
		LIKELY_SCRIPTS.put("uk", "Cyrl");
		LIKELY_SCRIPTS.put("be", "Cyrl");
		LIKELY_SCRIPTS.put("bg", "Cyrl");
		LIKELY_SCRIPTS.put("mk", "Cyrl");
		LIKELY_SCRIPTS.put("sr", "Cyrl");
		LIKELY_SCRIPTS.put("kk", "Cyrl");
		LIKELY_SCRIPTS.put("ky", "Cyrl");
		LIKELY_SCRIPTS.put("mn", "Cyrl");
		LIKELY_SCRIPTS.put("el", "Grek");
		LIKELY_SCRIPTS.put("he", "Hebr");
		LIKELY_SCRIPTS.put("iw", "Hebr");
		LIKELY_SCRIPTS.put("ar", "Arab");
		LIKELY_SCRIPTS.put("fa", "Arab");
		LIKELY_SCRIPTS.put("ur", "Arab");
		LIKELY_SCRIPTS.put("ps", "Arab");
		LIKELY_SCRIPTS.put("hy", "Armn");
		LIKELY_SCRIPTS.put("ka", "Geor");
		LIKELY_SCRIPTS.put("hi", "Deva");
		LIKELY_SCRIPTS.put("mr", "Deva");
		LIKELY_SCRIPTS.put("ne", "Deva");
		LIKELY_SCRIPTS.put("bn", "Beng");
		LIKELY_SCRIPTS.put("ta", "Taml");
		LIKELY_SCRIPTS.put("te", "Telu");
		LIKELY_SCRIPTS.put("th", "Thai");
		LIKELY_SCRIPTS.put("lo", "Laoo");
		LIKELY_SCRIPTS.put("my", "Mymr");
		LIKELY_SCRIPTS.put("km", "Khmr");
		LIKELY_SCRIPTS.put("ko", "Kore");
		LIKELY_SCRIPTS.put("ja", "Jpan");
		LIKELY_SCRIPTS.put("zh", "Hans");
	}

	private final Locale locale;

	private ULocale(Locale locale) {
		this.locale = locale;
	}

	public static ULocale forLocale(Locale locale) {
		return new ULocale(locale == null ? Locale.getDefault() : locale);
	}

	public static ULocale addLikelySubtags(ULocale ulocale) {
		Locale locale = ulocale.locale;
		if (!locale.getScript().isEmpty())
			return ulocale;

		String script = LIKELY_SCRIPTS.get(locale.getLanguage());
		if (script == null)
			script = locale.getLanguage().isEmpty() ? "" : "Latn";
		if (script.isEmpty())
			return ulocale;

		if ("zh".equals(locale.getLanguage())
		    && ("TW".equals(locale.getCountry()) || "HK".equals(locale.getCountry())
		        || "MO".equals(locale.getCountry()))) {
			script = "Hant";
		}
		return new ULocale(new Locale.Builder().setLocale(locale).setScript(script).build());
	}

	public String getScript() {
		return locale.getScript();
	}

	public String getLanguage() {
		return locale.getLanguage();
	}

	public Locale toLocale() {
		return locale;
	}

	@Override
	public String toString() {
		return locale.toString();
	}
}
