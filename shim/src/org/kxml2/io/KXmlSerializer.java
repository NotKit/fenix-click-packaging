package org.kxml2.io;

import org.xmlpull.v1.XmlSerializer;

import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.ArrayList;
import java.util.List;

/**
 * The XmlPull v1 serializer android.util.Xml.newSerializer() asks for by name
 * ("org.kxml2.io.KXmlParser,org.kxml2.io.KXmlSerializer"), written directly on
 * a Writer.
 *
 * Deviations from kXML2, none of which the callers here can see:
 * setPrefix/getPrefix keep a flat list of declarations and never generate a
 * prefix, so a document that needs one gets the default namespace instead;
 * indentation and the "serializer.indentation" property are not supported; and
 * docdecl/processingInstruction are written through verbatim rather than
 * checked.
 */
public class KXmlSerializer implements XmlSerializer {
	private Writer writer;
	private final List<String[]> declared = new ArrayList<>(); // {prefix, uri}, for lookup
	private final List<String[]> pending = new ArrayList<>();  // not yet written out
	private final List<String[]> open = new ArrayList<>();     // {namespace, name}
	private boolean startTagOpen;

	@Override
	public void setFeature(String name, boolean state) {
		if (state)
			throw new IllegalStateException("unsupported feature " + name);
	}

	@Override
	public boolean getFeature(String name) {
		return false;
	}

	@Override
	public void setProperty(String name, Object value) {
		throw new IllegalStateException("unsupported property " + name);
	}

	@Override
	public Object getProperty(String name) {
		return null;
	}

	@Override
	public void setOutput(OutputStream os, String encoding) throws IOException {
		setOutput(encoding == null ? new OutputStreamWriter(os)
		                           : new OutputStreamWriter(os, encoding));
	}

	@Override
	public void setOutput(Writer writer) {
		this.writer = writer;
		declared.clear();
		pending.clear();
		open.clear();
		startTagOpen = false;
	}

	@Override
	public void startDocument(String encoding, Boolean standalone) throws IOException {
		require().write("<?xml version='1.0'");
		if (encoding != null)
			writer.write(" encoding='" + encoding + "'");
		if (standalone != null)
			writer.write(" standalone='" + (standalone ? "yes" : "no") + "'");
		writer.write(" ?>");
	}

	@Override
	public void endDocument() throws IOException {
		while (!open.isEmpty()) {
			String[] tag = open.get(open.size() - 1);
			endTag(tag[0], tag[1]);
		}
		flush();
	}

	@Override
	public void setPrefix(String prefix, String namespace) throws IOException {
		String[] declaration = {prefix == null ? "" : prefix, namespace};
		declared.add(declaration);
		pending.add(declaration);
	}

	@Override
	public String getPrefix(String namespace, boolean generatePrefix) {
		for (int i = declared.size() - 1; i >= 0; i--) {
			if (declared.get(i)[1].equals(namespace))
				return declared.get(i)[0];
		}
		return null; // kXML2 would invent one here; see the class javadoc
	}

	@Override
	public int getDepth() {
		return open.size();
	}

	@Override
	public String getNamespace() {
		return open.isEmpty() ? null : open.get(open.size() - 1)[0];
	}

	@Override
	public String getName() {
		return open.isEmpty() ? null : open.get(open.size() - 1)[1];
	}

	@Override
	public XmlSerializer startTag(String namespace, String name) throws IOException {
		closeStartTag();
		require().write('<');
		writer.write(qualified(namespace, name));
		for (String[] ns : pending) {
			writer.write(ns[0].isEmpty() ? " xmlns='" : " xmlns:" + ns[0] + "='");
			writer.write(escape(ns[1], true));
			writer.write('\'');
		}
		pending.clear();
		open.add(new String[] {namespace, name});
		startTagOpen = true;
		return this;
	}

	@Override
	public XmlSerializer attribute(String namespace, String name, String value) throws IOException {
		if (!startTagOpen)
			throw new IllegalStateException("attribute outside a start tag");
		writer.write(' ');
		writer.write(qualified(namespace, name));
		writer.write("='");
		writer.write(escape(value, true));
		writer.write('\'');
		return this;
	}

	@Override
	public XmlSerializer endTag(String namespace, String name) throws IOException {
		if (open.isEmpty())
			throw new IllegalStateException("endTag with no open element");
		open.remove(open.size() - 1);
		if (startTagOpen) {
			require().write(" />");
			startTagOpen = false;
		} else {
			require().write("</");
			writer.write(qualified(namespace, name));
			writer.write('>');
		}
		return this;
	}

	@Override
	public XmlSerializer text(String text) throws IOException {
		closeStartTag();
		require().write(escape(text, false));
		return this;
	}

	@Override
	public XmlSerializer text(char[] buf, int start, int len) throws IOException {
		return text(new String(buf, start, len));
	}

	@Override
	public void cdsect(String text) throws IOException {
		closeStartTag();
		require().write("<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>");
	}

	@Override
	public void entityRef(String text) throws IOException {
		closeStartTag();
		require().write("&" + text + ";");
	}

	@Override
	public void processingInstruction(String text) throws IOException {
		closeStartTag();
		require().write("<?" + text + "?>");
	}

	@Override
	public void comment(String text) throws IOException {
		closeStartTag();
		require().write("<!--" + text + "-->");
	}

	@Override
	public void docdecl(String text) throws IOException {
		closeStartTag();
		require().write("<!DOCTYPE" + text + ">");
	}

	@Override
	public void ignorableWhitespace(String text) throws IOException {
		closeStartTag();
		require().write(text);
	}

	@Override
	public void flush() throws IOException {
		if (writer != null)
			writer.flush();
	}

	private Writer require() {
		if (writer == null)
			throw new IllegalStateException("setOutput has not been called");
		return writer;
	}

	private void closeStartTag() throws IOException {
		if (startTagOpen) {
			require().write('>');
			startTagOpen = false;
		}
	}

	private String qualified(String namespace, String name) {
		if (namespace == null || namespace.isEmpty())
			return name;
		String prefix = getPrefix(namespace, false);
		return prefix == null || prefix.isEmpty() ? name : prefix + ":" + name;
	}

	private static String escape(String value, boolean attribute) {
		StringBuilder out = new StringBuilder(value.length());
		for (int i = 0; i < value.length(); i++) {
			char c = value.charAt(i);
			switch (c) {
			case '&': out.append("&amp;"); break;
			case '<': out.append("&lt;"); break;
			case '>': out.append("&gt;"); break;
			case '\'': out.append(attribute ? "&apos;" : "'"); break;
			case '"': out.append(attribute ? "&quot;" : "\""); break;
			default:
				if (c < 0x20 && c != '\t' && c != '\n' && c != '\r')
					out.append("&#").append((int)c).append(';');
				else
					out.append(c);
			}
		}
		return out.toString();
	}
}
