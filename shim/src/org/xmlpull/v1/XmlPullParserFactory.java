package org.xmlpull.v1;

import java.util.ArrayList;
import java.util.HashMap;

/**
 * Creates parsers and serializers from a comma-separated list of class names,
 * the way android.util.Xml asks for them.
 *
 * Deviation from libcore: a name that cannot be loaded is skipped instead of
 * failing the whole factory, so a missing serializer does not take the parser
 * with it (see ../README.md, "deferred").
 */
public class XmlPullParserFactory {
	public static final String PROPERTY_NAME = "org.xmlpull.v1.XmlPullParserFactory";

	protected ArrayList parserClasses = new ArrayList();
	protected ArrayList serializerClasses = new ArrayList();
	protected String classNamesLocation;
	protected HashMap<String, Boolean> features = new HashMap<>();

	protected XmlPullParserFactory() {}

	public void setFeature(String name, boolean state) throws XmlPullParserException {
		features.put(name, state);
	}

	public boolean getFeature(String name) {
		return Boolean.TRUE.equals(features.get(name));
	}

	public void setNamespaceAware(boolean awareness) {
		features.put(XmlPullParser.FEATURE_PROCESS_NAMESPACES, awareness);
	}

	public boolean isNamespaceAware() {
		return getFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES);
	}

	public void setValidating(boolean validating) {
		features.put(XmlPullParser.FEATURE_VALIDATION, validating);
	}

	public boolean isValidating() {
		return getFeature(XmlPullParser.FEATURE_VALIDATION);
	}

	public XmlPullParser newPullParser() throws XmlPullParserException {
		XmlPullParser parser = (XmlPullParser)instantiate(parserClasses, "parser");
		for (java.util.Map.Entry<String, Boolean> feature : features.entrySet()) {
			if (feature.getValue() != null)
				parser.setFeature(feature.getKey(), feature.getValue());
		}
		return parser;
	}

	public XmlSerializer newSerializer() throws XmlPullParserException {
		return (XmlSerializer)instantiate(serializerClasses, "serializer");
	}

	public static XmlPullParserFactory newInstance() throws XmlPullParserException {
		return newInstance("org.kxml2.io.KXmlParser", null);
	}

	public static XmlPullParserFactory newInstance(String classNames, Class context)
	    throws XmlPullParserException {
		XmlPullParserFactory factory = new XmlPullParserFactory();
		factory.classNamesLocation = classNames;
		if (classNames == null)
			return factory;

		for (String name : classNames.split(",")) {
			name = name.trim();
			if (name.isEmpty())
				continue;
			try {
				Class<?> cls = Class.forName(name);
				if (XmlPullParser.class.isAssignableFrom(cls))
					factory.parserClasses.add(cls);
				else if (XmlSerializer.class.isAssignableFrom(cls))
					factory.serializerClasses.add(cls);
			} catch (ClassNotFoundException | LinkageError ignored) {
				// not part of the shim; the factory still serves whatever loaded
			}
		}
		return factory;
	}

	private Object instantiate(ArrayList classes, String what) throws XmlPullParserException {
		if (classes.isEmpty())
			throw new XmlPullParserException("no " + what + " in " + classNamesLocation
			    + " is provided by the desktop port shim");
		try {
			return ((Class<?>)classes.get(0)).getDeclaredConstructor().newInstance();
		} catch (Exception e) {
			throw new XmlPullParserException("could not create a " + what, null, e);
		}
	}
}
