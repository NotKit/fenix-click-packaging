package fenixni;

import java.security.Provider;
import java.security.Security;

import org.graalvm.nativeimage.hosted.Feature;

/**
 * Installs atlas's AndroidKeyStore JCE provider into the *builder's* provider
 * list, so the image carries a verification result for it.
 *
 * -H:AdditionalSecurityProviders alone is not enough, and the reason is worth
 * writing down: SecurityServicesFeature only consults that option in
 * shouldRemoveProvider(), i.e. to keep a provider that is already installed at
 * build time from being filtered out of the image. It never adds one. The
 * verification cache javax.crypto.JceSecurity carries into the image is built
 * from the providers installed *then*, so a provider that atlas installs at run
 * time -- Context.java does Security.addProvider(new AndroidKeyStoreProvider())
 * -- is a provider the image has never verified, and the first
 * KeyGenerator.getInstance() gets
 *
 *     UnsupportedFeatureError: Trying to verify a provider that was not
 *     registered at build time: AndroidKeyStore version 1.0
 *
 * Installing the same provider here fixes both ends: the cache gets an entry,
 * and atlas's run-time addProvider() becomes a no-op, because Security.addProvider
 * does nothing when a provider of that name is already installed -- so the
 * instance the image verified is the instance the app uses.
 *
 * Reflection rather than a direct reference: this must still build against a
 * framework older than atlas 86480a1d, which had no named provider class.
 */
public class KeyStoreProviderFeature implements Feature {

	private static final String PROVIDER = "android.security.keystore.AndroidKeyStoreProvider";

	@Override
	public void afterRegistration(AfterRegistrationAccess access) {
		if (Security.getProvider("AndroidKeyStore") != null)
			return;
		try {
			Class<?> cls = Class.forName(PROVIDER, true, getClass().getClassLoader());
			Security.addProvider((Provider)cls.getDeclaredConstructor().newInstance());
			System.out.println("fenixni: installed " + PROVIDER + " for the builder");
		} catch (ReflectiveOperationException e) {
			System.out.println("fenixni: no " + PROVIDER + " in this framework (" + e + ")");
		}
	}
}
