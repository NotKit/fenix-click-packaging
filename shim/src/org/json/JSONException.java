package org.json;

/** Thrown when the JSON in hand is not what the caller asked for. */
public class JSONException extends Exception {

	public JSONException(String s) {
		super(s);
	}

	public JSONException(String message, Throwable cause) {
		super(message, cause);
	}

	public JSONException(Throwable cause) {
		super(cause == null ? null : cause.toString(), cause);
	}
}
