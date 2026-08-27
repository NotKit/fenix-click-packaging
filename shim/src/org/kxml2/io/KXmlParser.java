package org.kxml2.io;

import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserException;

import java.io.IOException;
import java.io.InputStream;
import java.io.Reader;

import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamConstants;
import javax.xml.stream.XMLStreamException;
import javax.xml.stream.XMLStreamReader;

/**
 * The pull parser android.util.Xml hands out, on top of the JDK's StAX instead
 * of kXML2 (which lives on Android's boot classpath).
 *
 * Differences from kXML2, none of which the port's callers depend on:
 * isEmptyElementTag() always reports false because StAX does not expose it,
 * getNamespaceCount() only counts declarations on the current element, and
 * defineEntityReplacementText() is ignored.
 */
public class KXmlParser implements XmlPullParser {
	private static final String FEATURE_RELAXED = "http://xmlpull.org/v1/doc/features.html#relaxed";

	private XMLStreamReader reader;
	private String encoding;
	private boolean namespaceAware = true;
	private boolean processDocdecl;

	private int event = START_DOCUMENT;
	private int depth;
	private boolean pendingPop;
	private String text;

	public KXmlParser() {}

	// --- configuration ---

	@Override
	public void setFeature(String name, boolean state) throws XmlPullParserException {
		if (FEATURE_PROCESS_NAMESPACES.equals(name))
			namespaceAware = state;
		else if (FEATURE_PROCESS_DOCDECL.equals(name))
			processDocdecl = state;
		else if (FEATURE_RELAXED.equals(name) || FEATURE_REPORT_NAMESPACE_ATTRIBUTES.equals(name))
			; // accepted and ignored, as kXML2 does for relaxed parsing
		else if (FEATURE_VALIDATION.equals(name) && state)
			throw new XmlPullParserException("validation is not supported");
		else if (state)
			throw new XmlPullParserException("unsupported feature: " + name);
	}

	@Override
	public boolean getFeature(String name) {
		if (FEATURE_PROCESS_NAMESPACES.equals(name))
			return namespaceAware;
		if (FEATURE_PROCESS_DOCDECL.equals(name))
			return processDocdecl;
		return false;
	}

	@Override
	public void setProperty(String name, Object value) throws XmlPullParserException {
		throw new XmlPullParserException("unsupported property: " + name);
	}

	@Override
	public Object getProperty(String name) {
		return null;
	}

	@Override
	public void setInput(Reader in) throws XmlPullParserException {
		try {
			reset();
			reader = factory().createXMLStreamReader(in);
		} catch (XMLStreamException e) {
			throw new XmlPullParserException("could not read the document", this, e);
		}
	}

	@Override
	public void setInput(InputStream inputStream, String inputEncoding) throws XmlPullParserException {
		try {
			reset();
			encoding = inputEncoding;
			reader = inputEncoding == null ? factory().createXMLStreamReader(inputStream)
			                               : factory().createXMLStreamReader(inputStream, inputEncoding);
		} catch (XMLStreamException e) {
			throw new XmlPullParserException("could not read the document", this, e);
		}
	}

	private void reset() {
		reader = null;
		encoding = null;
		event = START_DOCUMENT;
		depth = 0;
		pendingPop = false;
		text = null;
	}

	private XMLInputFactory factory() {
		XMLInputFactory factory = XMLInputFactory.newInstance();
		factory.setProperty(XMLInputFactory.IS_NAMESPACE_AWARE, namespaceAware);
		factory.setProperty(XMLInputFactory.IS_COALESCING, Boolean.TRUE);
		factory.setProperty(XMLInputFactory.IS_REPLACING_ENTITY_REFERENCES, Boolean.TRUE);
		factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, Boolean.FALSE);
		factory.setProperty(XMLInputFactory.SUPPORT_DTD, processDocdecl);
		return factory;
	}

	@Override
	public String getInputEncoding() {
		return encoding;
	}

	@Override
	public void defineEntityReplacementText(String entityName, String replacementText) {}

	// --- traversal ---

	@Override
	public int next() throws XmlPullParserException, IOException {
		return advance(false);
	}

	@Override
	public int nextToken() throws XmlPullParserException, IOException {
		return advance(true);
	}

	private int advance(boolean reportAll) throws XmlPullParserException {
		if (reader == null)
			throw new XmlPullParserException("setInput() was not called", this, null);
		if (event == END_DOCUMENT)
			throw new XmlPullParserException("next() called past END_DOCUMENT", this, null);

		if (pendingPop) {
			depth--;
			pendingPop = false;
		}
		text = null;

		try {
			while (reader.hasNext()) {
				switch (reader.next()) {
				case XMLStreamConstants.START_ELEMENT:
					depth++;
					return event = START_TAG;
				case XMLStreamConstants.END_ELEMENT:
					pendingPop = true;
					return event = END_TAG;
				case XMLStreamConstants.CHARACTERS:
				case XMLStreamConstants.CDATA:
				case XMLStreamConstants.SPACE:
				case XMLStreamConstants.ENTITY_REFERENCE:
					text = reader.getText();
					return event = TEXT;
				case XMLStreamConstants.COMMENT:
					if (!reportAll)
						continue;
					text = reader.getText();
					return event = COMMENT;
				case XMLStreamConstants.PROCESSING_INSTRUCTION:
					if (!reportAll)
						continue;
					text = reader.getPIData();
					return event = PROCESSING_INSTRUCTION;
				case XMLStreamConstants.DTD:
					if (!reportAll)
						continue;
					text = reader.getText();
					return event = DOCDECL;
				case XMLStreamConstants.END_DOCUMENT:
					return event = END_DOCUMENT;
				default:
					continue;
				}
			}
		} catch (XMLStreamException e) {
			throw new XmlPullParserException("malformed document", this, e);
		}
		return event = END_DOCUMENT;
	}

	@Override
	public int nextTag() throws XmlPullParserException, IOException {
		int type = next();
		if (type == TEXT && isWhitespace())
			type = next();
		if (type != START_TAG && type != END_TAG)
			throw new XmlPullParserException("expected a start or end tag", this, null);
		return type;
	}

	@Override
	public String nextText() throws XmlPullParserException, IOException {
		if (event != START_TAG)
			throw new XmlPullParserException("precondition: START_TAG", this, null);
		int type = next();
		if (type == TEXT) {
			String result = getText();
			if (next() != END_TAG)
				throw new XmlPullParserException("TEXT must be followed by END_TAG", this, null);
			return result;
		}
		if (type == END_TAG)
			return "";
		throw new XmlPullParserException("expected TEXT or END_TAG", this, null);
	}

	@Override
	public void require(int type, String namespace, String name) throws XmlPullParserException {
		if (type != event || (namespace != null && !namespace.equals(getNamespace()))
		    || (name != null && !name.equals(getName()))) {
			throw new XmlPullParserException(
			    "expected " + TYPES[type] + " " + name, this, null);
		}
	}

	@Override
	public int getEventType() {
		return event;
	}

	@Override
	public int getDepth() {
		return depth;
	}

	// --- current event ---

	@Override
	public String getName() {
		if (event != START_TAG && event != END_TAG)
			return null;
		return qualify(reader.getPrefix(), reader.getLocalName());
	}

	@Override
	public String getNamespace() {
		if (event != START_TAG && event != END_TAG)
			return null;
		String uri = reader.getNamespaceURI();
		return uri == null ? NO_NAMESPACE : uri;
	}

	@Override
	public String getPrefix() {
		if (event != START_TAG && event != END_TAG)
			return null;
		String prefix = reader.getPrefix();
		return prefix == null || prefix.isEmpty() ? null : prefix;
	}

	@Override
	public String getText() {
		return text;
	}

	@Override
	public char[] getTextCharacters(int[] holderForStartAndLength) {
		if (text == null) {
			holderForStartAndLength[0] = -1;
			holderForStartAndLength[1] = -1;
			return null;
		}
		holderForStartAndLength[0] = 0;
		holderForStartAndLength[1] = text.length();
		return text.toCharArray();
	}

	@Override
	public boolean isWhitespace() throws XmlPullParserException {
		if (text == null)
			throw new XmlPullParserException("no text in the current event", this, null);
		return text.isBlank();
	}

	@Override
	public boolean isEmptyElementTag() {
		return false;
	}

	// --- attributes ---

	@Override
	public int getAttributeCount() {
		return event == START_TAG ? reader.getAttributeCount() : -1;
	}

	@Override
	public String getAttributeName(int index) {
		return qualify(reader.getAttributePrefix(index), reader.getAttributeLocalName(index));
	}

	@Override
	public String getAttributeNamespace(int index) {
		String uri = reader.getAttributeNamespace(index);
		return uri == null ? NO_NAMESPACE : uri;
	}

	@Override
	public String getAttributePrefix(int index) {
		String prefix = reader.getAttributePrefix(index);
		return prefix == null || prefix.isEmpty() ? null : prefix;
	}

	@Override
	public String getAttributeType(int index) {
		return "CDATA";
	}

	@Override
	public boolean isAttributeDefault(int index) {
		return false;
	}

	@Override
	public String getAttributeValue(int index) {
		return reader.getAttributeValue(index);
	}

	@Override
	public String getAttributeValue(String namespace, String name) {
		if (event != START_TAG)
			throw new IndexOutOfBoundsException("current event is not START_TAG");
		if (namespace != null && !namespace.isEmpty())
			return reader.getAttributeValue(namespace, name);

		// no namespace asked for: match only attributes that have none
		for (int i = 0, n = reader.getAttributeCount(); i < n; i++) {
			String uri = reader.getAttributeNamespace(i);
			if ((uri == null || uri.isEmpty()) && reader.getAttributeLocalName(i).equals(name))
				return reader.getAttributeValue(i);
		}
		return null;
	}

	// --- namespaces ---

	@Override
	public int getNamespaceCount(int depth) {
		return event == START_TAG || event == END_TAG ? reader.getNamespaceCount() : 0;
	}

	@Override
	public String getNamespacePrefix(int pos) {
		return reader.getNamespacePrefix(pos);
	}

	@Override
	public String getNamespaceUri(int pos) {
		return reader.getNamespaceURI(pos);
	}

	@Override
	public String getNamespace(String prefix) {
		return reader == null ? null : reader.getNamespaceURI(prefix == null ? "" : prefix);
	}

	// --- position ---

	@Override
	public int getLineNumber() {
		return reader == null ? -1 : reader.getLocation().getLineNumber();
	}

	@Override
	public int getColumnNumber() {
		return reader == null ? -1 : reader.getLocation().getColumnNumber();
	}

	@Override
	public String getPositionDescription() {
		return TYPES[event] + (getName() == null ? "" : " <" + getName() + ">") + "@" + getLineNumber()
		    + ":" + getColumnNumber();
	}

	private String qualify(String prefix, String localName) {
		return prefix == null || prefix.isEmpty() || namespaceAware ? localName : prefix + ":" + localName;
	}
}
