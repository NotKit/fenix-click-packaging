package android.icu.text;

/**
 * The slice of ICU4J's Bidi that android.text.AndroidBidi uses, over
 * java.text.Bidi. The level constants keep ICU's values because AndroidBidi was
 * compiled against ICU and has them inlined.
 */
public class Bidi {
	public static final byte LTR = 0;
	public static final byte RTL = 1;
	public static final byte LEVEL_DEFAULT_LTR = 0x7e;
	public static final byte LEVEL_DEFAULT_RTL = 0x7f;

	private java.text.Bidi bidi;
	private byte paraLevel = LTR;

	public Bidi() {}

	public Bidi(int maxLength, int maxRunCount) {}

	public void setPara(char[] text, byte paraLevel, byte[] embeddingLevels) {
		int flags;
		switch (paraLevel) {
		case LEVEL_DEFAULT_LTR:
			flags = java.text.Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT;
			break;
		case LEVEL_DEFAULT_RTL:
			flags = java.text.Bidi.DIRECTION_DEFAULT_RIGHT_TO_LEFT;
			break;
		default:
			flags = (paraLevel & 1) == 0 ? java.text.Bidi.DIRECTION_LEFT_TO_RIGHT
			                             : java.text.Bidi.DIRECTION_RIGHT_TO_LEFT;
			break;
		}

		if (text == null || text.length == 0) {
			bidi = null;
			this.paraLevel = (byte)(flags == java.text.Bidi.DIRECTION_RIGHT_TO_LEFT ? RTL : LTR);
			return;
		}

		bidi = new java.text.Bidi(text, 0, embeddingLevels, 0, text.length, flags);
		this.paraLevel = (byte)bidi.getBaseLevel();
	}

	public byte getParaLevel() {
		return paraLevel;
	}

	public byte getLevelAt(int charIndex) {
		return bidi == null ? paraLevel : (byte)bidi.getLevelAt(charIndex);
	}

	public int getLength() {
		return bidi == null ? 0 : bidi.getLength();
	}
}
