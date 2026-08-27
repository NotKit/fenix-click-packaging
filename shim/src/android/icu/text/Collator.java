package android.icu.text;

import java.util.Comparator;
import java.util.Locale;

/** ICU4J's Collator over java.text.Collator, which does the same job on the JDK. */
public class Collator implements Comparator<Object> {
	public static final int PRIMARY = java.text.Collator.PRIMARY;
	public static final int SECONDARY = java.text.Collator.SECONDARY;
	public static final int TERTIARY = java.text.Collator.TERTIARY;
	public static final int IDENTICAL = java.text.Collator.IDENTICAL;

	private final java.text.Collator collator;

	protected Collator(java.text.Collator collator) {
		this.collator = collator;
	}

	public static Collator getInstance() {
		return new Collator(java.text.Collator.getInstance());
	}

	public static Collator getInstance(Locale locale) {
		return new Collator(java.text.Collator.getInstance(locale));
	}

	public int compare(String source, String target) {
		return collator.compare(source, target);
	}

	@Override
	public int compare(Object source, Object target) {
		return collator.compare(String.valueOf(source), String.valueOf(target));
	}

	public boolean equals(String source, String target) {
		return collator.equals(source, target);
	}

	public void setStrength(int strength) {
		collator.setStrength(strength);
	}

	public int getStrength() {
		return collator.getStrength();
	}
}
