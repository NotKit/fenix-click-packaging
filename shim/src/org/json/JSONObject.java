package org.json;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** A modifiable set of name/value mappings, in insertion order. */
public class JSONObject {

	private static final Double NEGATIVE_ZERO = -0d;

	/** A sentinel for a name that is mapped to JSON's null rather than absent. */
	public static final Object NULL = new Object() {
		@Override
		public boolean equals(Object o) {
			return o == this || o == null;
		}

		@Override
		public int hashCode() {
			return 0;
		}

		@Override
		public String toString() {
			return "null";
		}
	};

	private final LinkedHashMap<String, Object> nameValuePairs;

	public JSONObject() {
		nameValuePairs = new LinkedHashMap<>();
	}

	public JSONObject(Map<?, ?> copyFrom) {
		this();
		if (copyFrom == null)
			return;
		for (Map.Entry<?, ?> entry : copyFrom.entrySet()) {
			String key = (String)entry.getKey();
			if (key == null)
				throw new NullPointerException("key == null");
			nameValuePairs.put(key, wrap(entry.getValue()));
		}
	}

	public JSONObject(JSONTokener readFrom) throws JSONException {
		Object object = readFrom.nextValue();
		if (object instanceof JSONObject)
			nameValuePairs = ((JSONObject)object).nameValuePairs;
		else
			throw JSON.typeMismatch(object, "JSONObject");
	}

	public JSONObject(String json) throws JSONException {
		this(new JSONTokener(json));
	}

	public JSONObject(JSONObject copyFrom, String[] names) throws JSONException {
		this();
		for (String name : names) {
			Object value = copyFrom.opt(name);
			if (value != null)
				nameValuePairs.put(name, value);
		}
	}

	public int length() {
		return nameValuePairs.size();
	}

	public JSONObject put(String name, boolean value) throws JSONException {
		nameValuePairs.put(checkName(name), value);
		return this;
	}

	public JSONObject put(String name, double value) throws JSONException {
		nameValuePairs.put(checkName(name), JSON.checkDouble(value));
		return this;
	}

	public JSONObject put(String name, int value) throws JSONException {
		nameValuePairs.put(checkName(name), value);
		return this;
	}

	public JSONObject put(String name, long value) throws JSONException {
		nameValuePairs.put(checkName(name), value);
		return this;
	}

	public JSONObject put(String name, Object value) throws JSONException {
		if (value == null) {
			nameValuePairs.remove(name);
			return this;
		}
		if (value instanceof Number)
			JSON.checkDouble(((Number)value).doubleValue());
		nameValuePairs.put(checkName(name), value);
		return this;
	}

	public JSONObject putOpt(String name, Object value) throws JSONException {
		if (name == null || value == null)
			return this;
		return put(name, value);
	}

	/** Turns repeated puts of one name into an array, as org.json does. */
	public JSONObject accumulate(String name, Object value) throws JSONException {
		Object current = nameValuePairs.get(checkName(name));
		if (current == null)
			return put(name, value);

		if (current instanceof JSONArray) {
			((JSONArray)current).put(value);
		} else {
			JSONArray array = new JSONArray();
			array.put(current);
			array.put(value);
			nameValuePairs.put(name, array);
		}
		return this;
	}

	private String checkName(String name) throws JSONException {
		if (name == null)
			throw new JSONException("Names must be non-null");
		return name;
	}

	public Object remove(String name) {
		return nameValuePairs.remove(name);
	}

	public boolean isNull(String name) {
		Object value = nameValuePairs.get(name);
		return value == null || value == NULL;
	}

	public boolean has(String name) {
		return nameValuePairs.containsKey(name);
	}

	public Object get(String name) throws JSONException {
		Object result = nameValuePairs.get(name);
		if (result == null)
			throw new JSONException("No value for " + name);
		return result;
	}

	public Object opt(String name) {
		return nameValuePairs.get(name);
	}

	public boolean getBoolean(String name) throws JSONException {
		Object object = get(name);
		Boolean result = JSON.toBoolean(object);
		if (result == null)
			throw JSON.typeMismatch(name, object, "boolean");
		return result;
	}

	public boolean optBoolean(String name) {
		return optBoolean(name, false);
	}

	public boolean optBoolean(String name, boolean fallback) {
		Boolean result = JSON.toBoolean(opt(name));
		return result != null ? result : fallback;
	}

	public double getDouble(String name) throws JSONException {
		Object object = get(name);
		Double result = JSON.toDouble(object);
		if (result == null)
			throw JSON.typeMismatch(name, object, "double");
		return result;
	}

	public double optDouble(String name) {
		return optDouble(name, Double.NaN);
	}

	public double optDouble(String name, double fallback) {
		Double result = JSON.toDouble(opt(name));
		return result != null ? result : fallback;
	}

	public int getInt(String name) throws JSONException {
		Object object = get(name);
		Integer result = JSON.toInteger(object);
		if (result == null)
			throw JSON.typeMismatch(name, object, "int");
		return result;
	}

	public int optInt(String name) {
		return optInt(name, 0);
	}

	public int optInt(String name, int fallback) {
		Integer result = JSON.toInteger(opt(name));
		return result != null ? result : fallback;
	}

	public long getLong(String name) throws JSONException {
		Object object = get(name);
		Long result = JSON.toLong(object);
		if (result == null)
			throw JSON.typeMismatch(name, object, "long");
		return result;
	}

	public long optLong(String name) {
		return optLong(name, 0L);
	}

	public long optLong(String name, long fallback) {
		Long result = JSON.toLong(opt(name));
		return result != null ? result : fallback;
	}

	public String getString(String name) throws JSONException {
		Object object = get(name);
		String result = JSON.toString(object);
		if (result == null)
			throw JSON.typeMismatch(name, object, "String");
		return result;
	}

	public String optString(String name) {
		return optString(name, "");
	}

	public String optString(String name, String fallback) {
		String result = JSON.toString(opt(name));
		return result != null ? result : fallback;
	}

	public JSONArray getJSONArray(String name) throws JSONException {
		Object object = get(name);
		if (object instanceof JSONArray)
			return (JSONArray)object;
		throw JSON.typeMismatch(name, object, "JSONArray");
	}

	public JSONArray optJSONArray(String name) {
		Object object = opt(name);
		return object instanceof JSONArray ? (JSONArray)object : null;
	}

	public JSONObject getJSONObject(String name) throws JSONException {
		Object object = get(name);
		if (object instanceof JSONObject)
			return (JSONObject)object;
		throw JSON.typeMismatch(name, object, "JSONObject");
	}

	public JSONObject optJSONObject(String name) {
		Object object = opt(name);
		return object instanceof JSONObject ? (JSONObject)object : null;
	}

	public JSONArray toJSONArray(JSONArray names) throws JSONException {
		JSONArray result = new JSONArray();
		if (names == null)
			return null;
		int length = names.length();
		if (length == 0)
			return null;
		for (int i = 0; i < length; i++) {
			String name = JSON.toString(names.opt(i));
			result.put(opt(name));
		}
		return result;
	}

	public Iterator<String> keys() {
		return nameValuePairs.keySet().iterator();
	}

	public Set<String> keySet() {
		return nameValuePairs.keySet();
	}

	public JSONArray names() {
		return nameValuePairs.isEmpty() ? null : new JSONArray(new java.util.ArrayList<Object>(nameValuePairs.keySet()));
	}

	/** The document, or null if it could not be encoded. */
	@Override
	public String toString() {
		try {
			JSONStringer stringer = new JSONStringer();
			writeTo(stringer);
			return stringer.toString();
		} catch (JSONException e) {
			return null;
		}
	}

	public String toString(int indentSpaces) throws JSONException {
		JSONStringer stringer = new JSONStringer(indentSpaces);
		writeTo(stringer);
		return stringer.toString();
	}

	void writeTo(JSONStringer stringer) throws JSONException {
		stringer.object();
		for (Map.Entry<String, Object> entry : nameValuePairs.entrySet())
			stringer.key(entry.getKey()).value(entry.getValue());
		stringer.endObject();
	}

	public static String numberToString(Number number) throws JSONException {
		if (number == null)
			throw new JSONException("Number must be non-null");

		double doubleValue = number.doubleValue();
		JSON.checkDouble(doubleValue);

		// a negative zero has to survive the round trip
		if (number.equals(NEGATIVE_ZERO))
			return "-0";

		long longValue = number.longValue();
		if (doubleValue == longValue)
			return Long.toString(longValue);

		return number.toString();
	}

	static String numberToString(double number) throws JSONException {
		return numberToString(Double.valueOf(number));
	}

	public static String quote(String data) {
		return data == null ? "\"\"" : JSONStringer.quote(data);
	}

	/** Wraps a plain Java value in its JSON equivalent, or returns it unchanged. */
	public static Object wrap(Object o) {
		if (o == null)
			return NULL;
		if (o instanceof JSONArray || o instanceof JSONObject)
			return o;
		if (o.equals(NULL))
			return o;
		try {
			if (o instanceof java.util.Collection)
				return new JSONArray((java.util.Collection<?>)o);
			if (o.getClass().isArray())
				return new JSONArray(o);
			if (o instanceof Map)
				return new JSONObject((Map<?, ?>)o);
			if (o instanceof Boolean || o instanceof Byte || o instanceof Character
			    || o instanceof Double || o instanceof Float || o instanceof Integer
			    || o instanceof Long || o instanceof Short || o instanceof String)
				return o;
			if (o.getClass().getPackage().getName().startsWith("java."))
				return o.toString();
		} catch (Exception ignored) {
		}
		return null;
	}
}
