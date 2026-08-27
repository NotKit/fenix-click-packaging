// Single process, the way route A had to do it: GeckoRuntimeSettings pushes
// its own defaults after omni.ja, so only user.js wins.
user_pref("browser.tabs.remote.autostart", false);
user_pref("browser.tabs.remote.autostart.2", false);
user_pref("fission.autostart", false);
user_pref("dom.ipc.processCount", 1);
user_pref("dom.ipc.processPrelaunch.enabled", false);
user_pref("layers.gpu-process.enabled", false);
user_pref("network.process.enabled", false);
user_pref("media.rdd-process.enabled", false);
user_pref("media.utility-process.enabled", false);
user_pref("security.sandbox.content.level", 0);

// Keep Gecko off the Java MediaCodec PDM. AndroidDecoderModule is the only
// consumer of android.media.MediaCodec here, and its design does not fit ATL:
// CodecProxy binds a service that GeckoView declares android:process=":media",
// ATL runs it in-process, and MediaManager.onCreate then calls
// GeckoLoader.suppressCrashDialog, whose MOZ_RELEASE_ASSERT(IsMediaProcess())
// kills the browser (APKOpen.cpp:615). A missing JNI member on that path is
// fatal too -- AndroidBridge::GetStaticMethodID MOZ_CRASHes. With the PDM off,
// ffvpx serves mp3/flac/opus/vorbis/vp8/vp9/av1 and an AAC or H264 page gets
// "no decoder found" plus a media error event instead of a SIGSEGV.
user_pref("media.android-media-codec.enabled", false);
user_pref("media.android-media-codec.preferred", false);
user_pref("media.utility-android-media-codec.enabled", false);
// ffvpx has no AAC and no H264 decoder in this build, so stop negotiating
// containers that only carry them, and let MSE offer VP9 (off by default on
// mobile) so a site that has a WebM ladder uses it.
user_pref("media.mp4.enabled", false);
user_pref("media.hevc.enabled", false);
user_pref("media.mediasource.vp9.enabled", true);
// No GMP plugin ships in the payload, and it would want a child process.
user_pref("media.gmp.decoder.enabled", false);
