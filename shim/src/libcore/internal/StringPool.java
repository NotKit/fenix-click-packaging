package libcore.internal;

/**
 * libcore interns short strings here to keep JsonReader allocation-free. Nothing
 * depends on the pooling itself, so this just builds the string.
 */
public final class StringPool {
	public String get(char[] array, int offset, int count) {
		return new String(array, offset, count);
	}
}
