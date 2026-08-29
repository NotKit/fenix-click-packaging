// Default prefs for Gecko under the Android Translation Layer.
//
// stage-gecko.sh puts this at defaults/pref/atl-defaults.js inside omni.ja,
// which Preferences::InitInitialObjects reads (Preferences.cpp).  A pref file
// is the only place some of these can be set at all: StaticPrefs *_AtStartup
// values are frozen while InitInitialObjects runs.
//
// The click's user.js is the other half, and it carries what has to override
// GeckoRuntimeSettings -- which pushes its own defaults after omni.ja.

// Fonts come from the NDK font-match API, which the layer implements.
pref("gfx.font-list.use_font_match_api.force-enabled", true);

// Single process.  e10s itself is off via MOZ_FORCE_DISABLE_E10S in the
// environment -- nsAppRunner.cpp caches the answer on the first call and no
// pref can reach it in time -- these keep everything else in-process.
pref("browser.tabs.remote.autostart", false);
pref("browser.tabs.remote.autostart.2", false);
pref("dom.ipc.processCount", 1);
pref("dom.ipc.processPrelaunch.enabled", false);
pref("fission.autostart", false);
pref("layers.gpu-process.enabled", false);
pref("network.process.enabled", false);
pref("media.rdd-process.enabled", false);
pref("media.utility-process.enabled", false);
pref("security.sandbox.content.level", 0);

// Software WebRender.  The GL path works too (SWWR=0 when staging); software
// stays the default because it is the longer-tested one.
pref("gfx.webrender.software", true);
pref("layout.frame_rate", 60);

// Generic font families.  ANDROID is not defined when all.js is preprocessed
// in a Linux-hosted android-toolkit build, so greprefs.js gets the fontconfig
// block and font.name-list.serif.x-western is the literal alias "serif" -- a
// name fontconfig understands and gfxFT2FontList does not.  Every generic then
// resolves to 0 families and falls back to whichever face is first.
//
// This is the floor, for the first run before a profile exists.  The click's
// user.js carries the same thing for all 29 langGroups; without x-cyrillic
// there, a Russian page reaches per-character fallback and gets laid out in
// whatever face happens to cover Cyrillic.
pref("font.name-list.serif.x-western", "Noto Serif, DejaVu Serif, Liberation Serif");
pref("font.name-list.sans-serif.x-western", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
pref("font.name-list.monospace.x-western", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
pref("font.name-list.serif.x-cyrillic", "Noto Serif, DejaVu Serif, Liberation Serif");
pref("font.name-list.sans-serif.x-cyrillic", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
pref("font.name-list.monospace.x-cyrillic", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");
pref("font.name-list.serif.x-unicode", "Noto Serif, DejaVu Serif, Liberation Serif");
pref("font.name-list.sans-serif.x-unicode", "Roboto, Noto Sans, DejaVu Sans, Liberation Sans, Ubuntu");
pref("font.name-list.monospace.x-unicode", "Noto Sans Mono, DejaVu Sans Mono, Liberation Mono, Ubuntu Mono");

// WebGL.  gfxPlatform::InitWebGLConfig disables it whenever there is no GPU
// process and the run is not headless, which is exactly this configuration.
// The blocklist entry is llvmpipe, the only renderer here.
pref("webgl.allow-in-parent", true);
pref("webgl.ignore-blocklist", true);
pref("webgl.disable-fail-if-major-performance-caveat", true);
// The two Android SharedSurface types both need a real Android graphics stack
// under them: with either on, the canvas presents an empty buffer.  Off, the
// readback surface is used and a cleared canvas reads back its colour.
pref("webgl.enable-surface-texture", false);
pref("webgl.enable-egl-image", false);

// Autoplay.  geckoview-prefs.js turns on media.geckoview.autoplay.request, so
// AutoplayPolicy hands the decision to a GeckoView delegate that is not
// implemented here and every play() comes back NotAllowedError.
pref("media.geckoview.autoplay.request", false);
pref("media.autoplay.default", 0);
