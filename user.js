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

// Fonts. greprefs.js gets the fontconfig block in a Linux-hosted
// android-toolkit build, so every font.name-list.* is the literal alias
// "serif"/"sans-serif"/"monospace" -- names fontconfig understands and
// gfxFT2FontList does not. Every generic then resolved to 0 families and a
// Russian page fell through per-character fallback into TakaoPGothic, which
// lays Cyrillic out at CJK advance widths. Name real families, per langGroup:
// the ones run.sh stages into $ANDROID_ROOT/fonts.
user_pref("font.name-list.sans-serif.x-western", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-western", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-western", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-western", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-cyrillic", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-cyrillic", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-cyrillic", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-cyrillic", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.el", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.el", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.el", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.el", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-unicode", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-unicode", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-unicode", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-unicode", "Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.ar", "Noto Sans Arabic, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.ar", "Noto Serif Arabic, Noto Sans Arabic, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.ar", "Noto Sans Arabic, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.ar", "Noto Serif Arabic, Noto Sans Arabic, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.he", "Noto Sans Hebrew, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.he", "Noto Serif Hebrew, Noto Sans Hebrew, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.he", "Noto Sans Hebrew, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.he", "Noto Serif Hebrew, Noto Sans Hebrew, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.th", "Noto Sans Thai, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.th", "Noto Serif Thai, Noto Sans Thai, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.th", "Noto Sans Thai, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.th", "Noto Serif Thai, Noto Sans Thai, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-armn", "Noto Sans Armenian, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-armn", "Noto Serif Armenian, Noto Sans Armenian, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-armn", "Noto Sans Armenian, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-armn", "Noto Serif Armenian, Noto Sans Armenian, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-beng", "Noto Sans Bengali, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-beng", "Noto Serif Bengali, Noto Sans Bengali, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-beng", "Noto Sans Bengali, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-beng", "Noto Serif Bengali, Noto Sans Bengali, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-cans", "Noto Sans Canadian Aboriginal, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-cans", "Noto Serif Canadian Aboriginal, Noto Sans Canadian Aboriginal, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-cans", "Noto Sans Canadian Aboriginal, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-cans", "Noto Serif Canadian Aboriginal, Noto Sans Canadian Aboriginal, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-devanagari", "Noto Sans Devanagari, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-devanagari", "Noto Serif Devanagari, Noto Sans Devanagari, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-devanagari", "Noto Sans Devanagari, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-devanagari", "Noto Serif Devanagari, Noto Sans Devanagari, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-ethi", "Noto Sans Ethiopic, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-ethi", "Noto Serif Ethiopic, Noto Sans Ethiopic, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-ethi", "Noto Sans Ethiopic, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-ethi", "Noto Serif Ethiopic, Noto Sans Ethiopic, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-geor", "Noto Sans Georgian, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-geor", "Noto Serif Georgian, Noto Sans Georgian, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-geor", "Noto Sans Georgian, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-geor", "Noto Serif Georgian, Noto Sans Georgian, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-gujr", "Noto Sans Gujarati, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-gujr", "Noto Serif Gujarati, Noto Sans Gujarati, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-gujr", "Noto Sans Gujarati, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-gujr", "Noto Serif Gujarati, Noto Sans Gujarati, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-guru", "Noto Sans Gurmukhi, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-guru", "Noto Serif Gurmukhi, Noto Sans Gurmukhi, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-guru", "Noto Sans Gurmukhi, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-guru", "Noto Serif Gurmukhi, Noto Sans Gurmukhi, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-khmr", "Noto Sans Khmer, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-khmr", "Noto Serif Khmer, Noto Sans Khmer, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-khmr", "Noto Sans Khmer, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-khmr", "Noto Serif Khmer, Noto Sans Khmer, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-knda", "Noto Sans Kannada, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-knda", "Noto Serif Kannada, Noto Sans Kannada, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-knda", "Noto Sans Kannada, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-knda", "Noto Serif Kannada, Noto Sans Kannada, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-mlym", "Noto Sans Malayalam, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-mlym", "Noto Serif Malayalam, Noto Sans Malayalam, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-mlym", "Noto Sans Malayalam, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-mlym", "Noto Serif Malayalam, Noto Sans Malayalam, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-orya", "Noto Sans Oriya, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-orya", "Noto Serif Oriya, Noto Sans Oriya, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-orya", "Noto Sans Oriya, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-orya", "Noto Serif Oriya, Noto Sans Oriya, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-sinh", "Noto Sans Sinhala, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-sinh", "Noto Serif Sinhala, Noto Sans Sinhala, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-sinh", "Noto Sans Sinhala, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-sinh", "Noto Serif Sinhala, Noto Sans Sinhala, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-tamil", "Noto Sans Tamil, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-tamil", "Noto Serif Tamil, Noto Sans Tamil, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-tamil", "Noto Sans Tamil, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-tamil", "Noto Serif Tamil, Noto Sans Tamil, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-telu", "Noto Sans Telugu, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-telu", "Noto Serif Telugu, Noto Sans Telugu, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-telu", "Noto Sans Telugu, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-telu", "Noto Serif Telugu, Noto Sans Telugu, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-tibt", "Noto Sans Tibetan, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-tibt", "Noto Serif Tibetan, Noto Sans Tibetan, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-tibt", "Noto Sans Tibetan, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-tibt", "Noto Serif Tibetan, Noto Sans Tibetan, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.x-math", "Noto Sans Math, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.x-math", "Noto Serif Math, Noto Sans Math, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.x-math", "Noto Sans Math, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.x-math", "Noto Serif Math, Noto Sans Math, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.ja", "Noto Sans CJK JP, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.ja", "Noto Serif CJK JP, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.ja", "Noto Sans Mono CJK JP, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.ja", "Noto Serif CJK JP, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.ko", "Noto Sans CJK KR, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.ko", "Noto Serif CJK KR, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.ko", "Noto Sans Mono CJK KR, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.ko", "Noto Serif CJK KR, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.zh-CN", "Noto Sans CJK SC, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.zh-CN", "Noto Serif CJK SC, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.zh-CN", "Noto Sans Mono CJK SC, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.zh-CN", "Noto Serif CJK SC, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.zh-TW", "Noto Sans CJK TC, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.zh-TW", "Noto Serif CJK TC, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.zh-TW", "Noto Sans Mono CJK TC, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.zh-TW", "Noto Serif CJK TC, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.sans-serif.zh-HK", "Noto Sans CJK HK, Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
user_pref("font.name-list.serif.zh-HK", "Noto Serif CJK HK, Noto Serif, DejaVu Serif, Liberation Serif");
user_pref("font.name-list.monospace.zh-HK", "Noto Sans Mono CJK HK, Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
user_pref("font.name-list.cursive.zh-HK", "Noto Serif CJK HK, Noto Serif, DejaVu Serif, Liberation Serif");
