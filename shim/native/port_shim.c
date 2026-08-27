/*
 * JNI back end for the libcore shim jar (see ../README.md).
 *
 * Copied from ~/UT/mercurygram-src/linux-port/shim/native/port_shim.c at
 * 74af55a30 (read-only there); setsockoptInt and sysconf at the end are
 * firefox-atl's additions, for GeckoRuntime.startCrashHelper and Sentry.
 *
 * HotSpot has no libcore, so the handful of shim classes that cannot be written
 * in pure Java land here: calling a raw free-function pointer for
 * libcore.util.NativeAllocationRegistry, and the file-descriptor syscalls
 * libcore.io.Posix exposes to android.system.Os.
 */

#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

/* --- helpers ------------------------------------------------------------ */

static void throw_errno(JNIEnv *env, const char *function, int err) {
	jclass cls = (*env)->FindClass(env, "android/system/ErrnoException");
	if (cls == NULL)
		return; /* NoClassDefFoundError is already pending */
	jmethodID ctor = (*env)->GetMethodID(env, cls, "<init>", "(Ljava/lang/String;I)V");
	if (ctor == NULL)
		return;
	jstring name = (*env)->NewStringUTF(env, function);
	jobject e = (*env)->NewObject(env, cls, ctor, name, (jint)err);
	if (e != NULL)
		(*env)->Throw(env, (jthrowable)e);
}

/* java.io.FileDescriptor keeps the descriptor in a private int field; JNI is not
 * subject to access control, so read/write it directly instead of --add-opens. */
static jfieldID fd_field(JNIEnv *env) {
	static jfieldID cached;
	if (cached == NULL) {
		jclass cls = (*env)->FindClass(env, "java/io/FileDescriptor");
		if (cls == NULL)
			return NULL;
		cached = (*env)->GetFieldID(env, cls, "fd", "I");
	}
	return cached;
}

static int unwrap_fd(JNIEnv *env, jobject fd) {
	jfieldID f = fd_field(env);
	if (f == NULL || fd == NULL) {
		throw_errno(env, "fd", EBADF);
		return -1;
	}
	return (*env)->GetIntField(env, fd, f);
}

/* --- libcore.util.NativeAllocationRegistry ------------------------------ */

JNIEXPORT void JNICALL
Java_libcore_util_NativeAllocationRegistry_applyFreeFunction(JNIEnv *env, jclass cls,
                                                             jlong freeFunction, jlong nativePtr) {
	(void)env;
	(void)cls;
	void (*free_fn)(void *) = (void (*)(void *))(intptr_t)freeFunction;
	if (free_fn != NULL && nativePtr != 0)
		free_fn((void *)(intptr_t)nativePtr);
}

/* Self-test hook: hands out a malloc'd block and a counting free function so the
 * shim's own check can prove the Cleaner really reaches native code. */
static long free_calls;

static void counting_free(void *p) {
	free_calls++;
	free(p);
}

JNIEXPORT jlong JNICALL
Java_libcore_util_NativeAllocationRegistry_00024SelfTest_allocate(JNIEnv *env, jclass cls, jlong size) {
	(void)env;
	(void)cls;
	return (jlong)(intptr_t)malloc((size_t)size);
}

JNIEXPORT jlong JNICALL
Java_libcore_util_NativeAllocationRegistry_00024SelfTest_freeFunction(JNIEnv *env, jclass cls) {
	(void)env;
	(void)cls;
	return (jlong)(intptr_t)counting_free;
}

JNIEXPORT jlong JNICALL
Java_libcore_util_NativeAllocationRegistry_00024SelfTest_freeCalls(JNIEnv *env, jclass cls) {
	(void)env;
	(void)cls;
	return (jlong)free_calls;
}

/* --- libcore.io.Posix --------------------------------------------------- */

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_gettid(JNIEnv *env, jclass cls) {
	(void)env;
	(void)cls;
	return (jint)syscall(SYS_gettid);
}

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_fdOf(JNIEnv *env, jclass cls, jobject fd) {
	(void)cls;
	return unwrap_fd(env, fd);
}

JNIEXPORT jobject JNICALL
Java_libcore_io_Posix_fdFor(JNIEnv *env, jclass cls, jint fd) {
	(void)cls;
	jclass fdcls = (*env)->FindClass(env, "java/io/FileDescriptor");
	if (fdcls == NULL)
		return NULL;
	jmethodID ctor = (*env)->GetMethodID(env, fdcls, "<init>", "()V");
	jfieldID f = fd_field(env);
	if (ctor == NULL || f == NULL)
		return NULL;
	jobject obj = (*env)->NewObject(env, fdcls, ctor);
	if (obj != NULL)
		(*env)->SetIntField(env, obj, f, fd);
	return obj;
}

JNIEXPORT void JNICALL
Java_libcore_io_Posix_setFd(JNIEnv *env, jclass cls, jobject fd, jint value) {
	(void)cls;
	jfieldID f = fd_field(env);
	if (f != NULL && fd != NULL)
		(*env)->SetIntField(env, fd, f, value);
}

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_open(JNIEnv *env, jclass cls, jstring path, jint flags, jint mode) {
	(void)cls;
	const char *p = (*env)->GetStringUTFChars(env, path, NULL);
	if (p == NULL)
		return -1;
	int fd = open(p, flags, (mode_t)mode);
	int err = errno;
	(*env)->ReleaseStringUTFChars(env, path, p);
	if (fd < 0)
		throw_errno(env, "open", err);
	return fd;
}

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_dup(JNIEnv *env, jclass cls, jint fd) {
	(void)cls;
	int n = dup(fd);
	if (n < 0)
		throw_errno(env, "dup", errno);
	return n;
}

JNIEXPORT jintArray JNICALL
Java_libcore_io_Posix_pipe(JNIEnv *env, jclass cls) {
	(void)cls;
	int fds[2];
	if (pipe(fds) < 0) {
		throw_errno(env, "pipe", errno);
		return NULL;
	}
	jintArray out = (*env)->NewIntArray(env, 2);
	if (out != NULL)
		(*env)->SetIntArrayRegion(env, out, 0, 2, fds);
	return out;
}

JNIEXPORT jintArray JNICALL
Java_libcore_io_Posix_socketpair(JNIEnv *env, jclass cls, jint domain, jint type, jint protocol) {
	(void)cls;
	int fds[2];
	if (socketpair(domain, type, protocol, fds) < 0) {
		throw_errno(env, "socketpair", errno);
		return NULL;
	}
	jintArray out = (*env)->NewIntArray(env, 2);
	if (out != NULL)
		(*env)->SetIntArrayRegion(env, out, 0, 2, fds);
	return out;
}

JNIEXPORT jlong JNICALL
Java_libcore_io_Posix_lseek(JNIEnv *env, jclass cls, jint fd, jlong offset, jint whence) {
	(void)cls;
	off_t pos = lseek(fd, (off_t)offset, whence);
	if (pos < 0)
		throw_errno(env, "lseek", errno);
	return (jlong)pos;
}

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_read(JNIEnv *env, jclass cls, jint fd, jbyteArray buf, jint off, jint len) {
	(void)cls;
	jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
	if (b == NULL)
		return -1;
	ssize_t n = read(fd, b + off, (size_t)len);
	int err = errno;
	(*env)->ReleaseByteArrayElements(env, buf, b, 0);
	if (n < 0)
		throw_errno(env, "read", err);
	return (jint)n;
}

JNIEXPORT jint JNICALL
Java_libcore_io_Posix_write(JNIEnv *env, jclass cls, jint fd, jbyteArray buf, jint off, jint len) {
	(void)cls;
	jbyte *b = (*env)->GetByteArrayElements(env, buf, NULL);
	if (b == NULL)
		return -1;
	ssize_t n = write(fd, b + off, (size_t)len);
	int err = errno;
	(*env)->ReleaseByteArrayElements(env, buf, b, JNI_ABORT);
	if (n < 0)
		throw_errno(env, "write", err);
	return (jint)n;
}

JNIEXPORT void JNICALL
Java_libcore_io_Posix_close(JNIEnv *env, jclass cls, jint fd) {
	(void)cls;
	if (close(fd) < 0)
		throw_errno(env, "close", errno);
}

JNIEXPORT void JNICALL
Java_libcore_io_Posix_setBlocking(JNIEnv *env, jclass cls, jint fd, jboolean blocking) {
	(void)cls;
	int flags = fcntl(fd, F_GETFL);
	if (flags < 0) {
		throw_errno(env, "fcntl", errno);
		return;
	}
	flags = blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK);
	if (fcntl(fd, F_SETFL, flags) < 0)
		throw_errno(env, "fcntl", errno);
}

/* st_mode, st_size, st_mtime — the three fields api-impl reads. */
JNIEXPORT jlongArray JNICALL
Java_libcore_io_Posix_fstat(JNIEnv *env, jclass cls, jint fd) {
	(void)cls;
	struct stat st;
	if (fstat(fd, &st) < 0) {
		throw_errno(env, "fstat", errno);
		return NULL;
	}
	jlong values[3] = {(jlong)st.st_mode, (jlong)st.st_size, (jlong)st.st_mtime};
	jlongArray out = (*env)->NewLongArray(env, 3);
	if (out != NULL)
		(*env)->SetLongArrayRegion(env, out, 0, 3, values);
	return out;
}

JNIEXPORT void JNICALL
Java_libcore_io_Posix_setsockoptInt(JNIEnv *env, jclass cls, jint fd, jint level, jint option,
                                    jint value) {
	(void)cls;
	int v = value;
	if (setsockopt(fd, level, option, &v, sizeof(v)) < 0)
		throw_errno(env, "setsockopt", errno);
}

/* The names are glibc's _SC_* (android/system/OsConstants), because this is the
 * host libc; bionic numbers them differently. */
JNIEXPORT jlong JNICALL
Java_libcore_io_Posix_sysconf(JNIEnv *env, jclass cls, jint name) {
	(void)env;
	(void)cls;
	return (jlong)sysconf(name);
}

/* libcore.io.Memory's raw-address accessors. ART's are native for the same
 * reason: a JVM cannot dereference an address in pure Java. Nothing in ATL or
 * Fenix calls them -- protobuf-javalite reflects for their *presence* to decide
 * it is on Android (see src/libcore/io/Memory.java). The unaligned cases go
 * through memcpy, as AOSP's Memory.cpp does; the byte-count and offset checks
 * are done on the Java side. */
JNIEXPORT jbyte JNICALL
Java_libcore_io_Memory_peekByte(JNIEnv *env, jclass cls, jlong address) {
	(void)env;
	(void)cls;
	return *(const jbyte *)(intptr_t)address;
}

JNIEXPORT void JNICALL
Java_libcore_io_Memory_pokeByte(JNIEnv *env, jclass cls, jlong address, jbyte value) {
	(void)env;
	(void)cls;
	*(jbyte *)(intptr_t)address = value;
}

JNIEXPORT jint JNICALL
Java_libcore_io_Memory_peekIntNative(JNIEnv *env, jclass cls, jlong address) {
	(void)env;
	(void)cls;
	jint value;
	memcpy(&value, (const void *)(intptr_t)address, sizeof(value));
	return value;
}

JNIEXPORT void JNICALL
Java_libcore_io_Memory_pokeIntNative(JNIEnv *env, jclass cls, jlong address, jint value) {
	(void)env;
	(void)cls;
	memcpy((void *)(intptr_t)address, &value, sizeof(value));
}

JNIEXPORT jlong JNICALL
Java_libcore_io_Memory_peekLongNative(JNIEnv *env, jclass cls, jlong address) {
	(void)env;
	(void)cls;
	jlong value;
	memcpy(&value, (const void *)(intptr_t)address, sizeof(value));
	return value;
}

JNIEXPORT void JNICALL
Java_libcore_io_Memory_pokeLongNative(JNIEnv *env, jclass cls, jlong address, jlong value) {
	(void)env;
	(void)cls;
	memcpy((void *)(intptr_t)address, &value, sizeof(value));
}

JNIEXPORT void JNICALL
Java_libcore_io_Memory_peekByteArrayNative(JNIEnv *env, jclass cls, jlong address, jbyteArray dst,
                                           jint dstOffset, jint byteCount) {
	(void)cls;
	(*env)->SetByteArrayRegion(env, dst, dstOffset, byteCount,
	                           (const jbyte *)(intptr_t)address);
}

JNIEXPORT void JNICALL
Java_libcore_io_Memory_pokeByteArrayNative(JNIEnv *env, jclass cls, jlong address, jbyteArray src,
                                           jint srcOffset, jint byteCount) {
	(void)cls;
	(*env)->GetByteArrayRegion(env, src, srcOffset, byteCount, (jbyte *)(intptr_t)address);
}
