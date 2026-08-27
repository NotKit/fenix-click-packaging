package org.apache.harmony.xml.parsers;

import javax.xml.parsers.ParserConfigurationException;
import javax.xml.parsers.SAXParser;
import javax.xml.parsers.SAXParserFactory;
import org.xml.sax.SAXException;
import org.xml.sax.SAXNotRecognizedException;
import org.xml.sax.SAXNotSupportedException;

/**
 * The SAX factory Android's libcore installs as the JAXP default, over the JDK's.
 *
 * <p>Only one behaviour of it matters here, and it is not optional: libcore's
 * parser is Expat, which always passes the element name as {@code localName},
 * namespace-aware or not. Xerces leaves {@code localName} empty unless the
 * factory is namespace-aware, so app code written against Android that switches
 * on {@code localName} silently matches nothing — {@code SvgHelper} parses every
 * SVG into an empty drawable that way, and the first caller indexing into it
 * kills the process.
 *
 * <p>This delegates to the JDK's own implementation with namespaces always on,
 * which fills in both {@code localName} and {@code qName} the way Expat does.
 * {@link #isNamespaceAware()} still answers what the caller asked for.
 *
 * <p>Registered through {@code META-INF/services/javax.xml.parsers.SAXParserFactory}
 * in the shim jar, so {@code SAXParserFactory.newInstance()} finds it exactly
 * like {@code newInstance()} finds this class on ART.
 */
public class SAXParserFactoryImpl extends SAXParserFactory {

	private final SAXParserFactory delegate = SAXParserFactory.newDefaultInstance();
	private boolean namespaceAware;

	public SAXParserFactoryImpl() {
		delegate.setNamespaceAware(true);
	}

	@Override
	public SAXParser newSAXParser() throws ParserConfigurationException, SAXException {
		return delegate.newSAXParser();
	}

	@Override
	public void setNamespaceAware(boolean awareness) {
		// remembered, not applied: turning it off is what empties localName
		namespaceAware = awareness;
	}

	@Override
	public boolean isNamespaceAware() {
		return namespaceAware;
	}

	@Override
	public void setValidating(boolean validating) {
		delegate.setValidating(validating);
	}

	@Override
	public boolean isValidating() {
		return delegate.isValidating();
	}

	@Override
	public void setFeature(String name, boolean value)
			throws ParserConfigurationException, SAXNotRecognizedException, SAXNotSupportedException {
		delegate.setFeature(name, value);
	}

	@Override
	public boolean getFeature(String name)
			throws ParserConfigurationException, SAXNotRecognizedException, SAXNotSupportedException {
		return delegate.getFeature(name);
	}
}
