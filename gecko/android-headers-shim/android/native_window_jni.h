/* Route B: the NDK's <android/native_window_jni.h>, which ATL's header tree
 * does not carry.  ATL implements these in libandroid.so.0. */
#ifndef ATL_SHIM_ANDROID_NATIVE_WINDOW_JNI_H
#define ATL_SHIM_ANDROID_NATIVE_WINDOW_JNI_H

#include <android/native_window.h>
#include <jni.h>

#include "../ndk-shim.h"
ATL_NDK_VISIBILITY_PUSH

#ifdef __cplusplus
extern "C" {
#endif

ANativeWindow* ANativeWindow_fromSurface(JNIEnv* env, jobject surface);
ANativeWindow* ANativeWindow_fromSurfaceTexture(JNIEnv* env, jobject surfaceTexture);
jobject ANativeWindow_toSurface(JNIEnv* env, ANativeWindow* window);

#ifdef __cplusplus
}
#endif

ATL_NDK_VISIBILITY_POP

#endif
