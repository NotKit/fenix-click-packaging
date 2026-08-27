package android.icu.text;

/**
 * ICU's capitalization display contexts.
 *
 * Only the capitalization family is here, because that is all the shim's
 * {@link DateFormat} can act on; ICU's other DisplayContext groups (dialect
 * handling, name length, substitution) are not declared. The shim's DateFormat
 * ignores the setting entirely -- java.text.SimpleDateFormat has no
 * capitalization control -- so a standalone month name comes out in the JDK's
 * formatting case rather than ICU's stand-alone case.
 */
public enum DisplayContext {
	CAPITALIZATION_NONE,
	CAPITALIZATION_FOR_MIDDLE_OF_SENTENCE,
	CAPITALIZATION_FOR_BEGINNING_OF_SENTENCE,
	CAPITALIZATION_FOR_UI_LIST_OR_MENU,
	CAPITALIZATION_FOR_STANDALONE
}
