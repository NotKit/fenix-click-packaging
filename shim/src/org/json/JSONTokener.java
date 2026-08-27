package org.json;

/**
 * Parses a JSON document out of a string.
 *
 * As lenient as the Android implementation: comments, single quotes, unquoted
 * names and semicolons are all accepted, because apps rely on documents that a
 * strict parser would reject.
 */
public class JSONTokener {

	private final String in;
	private int pos;

	public JSONTokener(String in) {
		// consume an optional byte order mark, as the Android parser does
		if (in != null && in.startsWith("﻿"))
			in = in.substring(1);
		this.in = in;
	}

	public Object nextValue() throws JSONException {
		int c = nextCleanInternal();
		switch (c) {
		case -1:
			throw syntaxError("End of input");
		case '{':
			return readObject();
		case '[':
			return readArray();
		case '\'':
		case '"':
			return nextString((char)c);
		default:
			pos--;
			return readLiteral();
		}
	}

	private int nextCleanInternal() throws JSONException {
		while (pos < in.length()) {
			int c = in.charAt(pos++);
			switch (c) {
			case '\t':
			case ' ':
			case '\n':
			case '\r':
				continue;

			case '/':
				if (pos == in.length())
					return c;

				char peek = in.charAt(pos);
				if (peek == '*') {
					pos++;
					int commentEnd = in.indexOf("*/", pos);
					if (commentEnd == -1)
						throw syntaxError("Unterminated comment");
					pos = commentEnd + 2;
					continue;
				} else if (peek == '/') {
					pos++;
					skipToEndOfLine();
					continue;
				}
				return c;

			case '#':
				// python-style comments; Android's parser allows them
				skipToEndOfLine();
				continue;

			default:
				return c;
			}
		}
		return -1;
	}

	private void skipToEndOfLine() {
		for (; pos < in.length(); pos++) {
			char c = in.charAt(pos);
			if (c == '\r' || c == '\n') {
				pos++;
				break;
			}
		}
	}

	public String nextString(char quote) throws JSONException {
		StringBuilder builder = null;
		int start = pos;

		while (pos < in.length()) {
			int c = in.charAt(pos++);
			if (c == quote) {
				if (builder == null)
					return in.substring(start, pos - 1); // a fast path for the common case
				builder.append(in, start, pos - 1);
				return builder.toString();
			}

			if (c == '\\') {
				if (pos == in.length())
					throw syntaxError("Unterminated escape sequence");
				if (builder == null)
					builder = new StringBuilder();
				builder.append(in, start, pos - 1);
				builder.append(readEscapeCharacter());
				start = pos;
			}
		}

		throw syntaxError("Unterminated string");
	}

	private char readEscapeCharacter() throws JSONException {
		char escaped = in.charAt(pos++);
		switch (escaped) {
		case 'u':
			if (pos + 4 > in.length())
				throw syntaxError("Unterminated escape sequence");
			String hex = in.substring(pos, pos + 4);
			pos += 4;
			try {
				return (char)Integer.parseInt(hex, 16);
			} catch (NumberFormatException e) {
				throw syntaxError("Invalid escape sequence: " + hex);
			}
		case 't':
			return '\t';
		case 'b':
			return '\b';
		case 'n':
			return '\n';
		case 'r':
			return '\r';
		case 'f':
			return '\f';
		default:
			return escaped;
		}
	}

	/** An unquoted run: true, false, null or a number, else a bare string. */
	private Object readLiteral() throws JSONException {
		String literal = nextToInternal("{}[]/\\:,=;# \t\f");

		if (literal.isEmpty())
			throw syntaxError("Expected literal value");
		if ("null".equalsIgnoreCase(literal))
			return JSONObject.NULL;
		if ("true".equalsIgnoreCase(literal))
			return Boolean.TRUE;
		if ("false".equalsIgnoreCase(literal))
			return Boolean.FALSE;

		if (literal.indexOf('.') == -1) {
			int base = 10;
			String number = literal;
			if (number.startsWith("0x") || number.startsWith("0X")) {
				number = number.substring(2);
				base = 16;
			} else if (number.startsWith("0") && number.length() > 1) {
				number = number.substring(1);
				base = 8;
			}
			try {
				long longValue = Long.parseLong(number, base);
				if (longValue <= Integer.MAX_VALUE && longValue >= Integer.MIN_VALUE)
					return (int)longValue;
				return longValue;
			} catch (NumberFormatException ignored) {
				// fall through to a double, then to the string itself
			}
		}

		try {
			return Double.valueOf(literal);
		} catch (NumberFormatException ignored) {
		}

		return literal;
	}

	private String nextToInternal(String excluded) {
		int start = pos;
		for (; pos < in.length(); pos++) {
			char c = in.charAt(pos);
			if (c == '\r' || c == '\n' || excluded.indexOf(c) != -1)
				return in.substring(start, pos);
		}
		return in.substring(start);
	}

	private JSONObject readObject() throws JSONException {
		JSONObject result = new JSONObject();

		int first = nextCleanInternal();
		if (first == '}')
			return result;
		if (first != -1)
			pos--;

		while (true) {
			Object name = nextValue();
			if (!(name instanceof String)) {
				if (name == null)
					throw syntaxError("Names cannot be null");
				throw syntaxError("Names must be strings, but " + name + " is of type "
				                  + name.getClass().getName());
			}

			int separator = nextCleanInternal();
			if (separator != ':' && separator != '=')
				throw syntaxError("Expected ':' after " + name);
			if (pos < in.length() && in.charAt(pos) == '>')
				pos++;

			result.put((String)name, nextValue());

			switch (nextCleanInternal()) {
			case '}':
				return result;
			case ';':
			case ',':
				continue;
			default:
				throw syntaxError("Unterminated object");
			}
		}
	}

	private JSONArray readArray() throws JSONException {
		JSONArray result = new JSONArray();

		boolean hasTrailingSeparator = false;
		while (true) {
			switch (nextCleanInternal()) {
			case -1:
				throw syntaxError("Unterminated array");
			case ']':
				if (hasTrailingSeparator)
					result.put((Object)null);
				return result;
			case ',':
			case ';':
				// a missing element is a null one
				result.put((Object)null);
				hasTrailingSeparator = true;
				continue;
			default:
				pos--;
			}

			result.put(nextValue());

			switch (nextCleanInternal()) {
			case ']':
				return result;
			case ',':
			case ';':
				hasTrailingSeparator = true;
				continue;
			default:
				throw syntaxError("Unterminated array");
			}
		}
	}

	public JSONException syntaxError(String message) {
		return new JSONException(message + this);
	}

	@Override
	public String toString() {
		return " at character " + pos + " of " + in;
	}

	/* --- the rest of the org.json API, kept for apps that drive the tokener --- */

	public boolean more() {
		return pos < in.length();
	}

	public char next() {
		return pos < in.length() ? in.charAt(pos++) : '\0';
	}

	public char next(char c) throws JSONException {
		char result = next();
		if (result != c)
			throw syntaxError("Expected " + c + " but was " + result);
		return result;
	}

	public char nextClean() throws JSONException {
		int nextCleanInt = nextCleanInternal();
		return nextCleanInt == -1 ? '\0' : (char)nextCleanInt;
	}

	public String next(int length) throws JSONException {
		if (pos + length > in.length())
			throw syntaxError(length + " is out of bounds");
		String result = in.substring(pos, pos + length);
		pos += length;
		return result;
	}

	public String nextTo(String excluded) {
		if (excluded == null)
			throw new NullPointerException("excluded == null");
		return nextToInternal(excluded).trim();
	}

	public String nextTo(char excluded) {
		return nextToInternal(String.valueOf(excluded)).trim();
	}

	public void skipPast(String thru) {
		int thruStart = in.indexOf(thru, pos);
		pos = thruStart == -1 ? in.length() : (thruStart + thru.length());
	}

	public char skipTo(char to) {
		int index = in.indexOf(to, pos);
		if (index != -1) {
			pos = index;
			return to;
		}
		return '\0';
	}

	public void back() {
		if (--pos == -1)
			pos = 0;
	}

	public static int dehexchar(char hex) {
		if (hex >= '0' && hex <= '9')
			return hex - '0';
		if (hex >= 'A' && hex <= 'F')
			return hex - 'A' + 10;
		if (hex >= 'a' && hex <= 'f')
			return hex - 'a' + 10;
		return -1;
	}
}
