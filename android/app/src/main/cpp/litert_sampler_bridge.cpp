#include <android/log.h>
#include <jni.h>
#include <dlfcn.h>

constexpr char kTag[] = "LiteRtSamplerBridge";

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM*, void*) {
  __android_log_print(ANDROID_LOG_INFO, kTag, "JNI_OnLoad started, attempting to load libraries with RTLD_GLOBAL");

  void* core_handle = dlopen("libLiteRt.so", RTLD_NOW | RTLD_GLOBAL);
  if (!core_handle) {
      __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to load libLiteRt.so: %s", dlerror());
  } else {
      __android_log_print(ANDROID_LOG_INFO, kTag, "Successfully loaded libLiteRt.so globally");
  }

  void* cl_handle = dlopen("libLiteRtTopKOpenClSampler.so", RTLD_NOW | RTLD_GLOBAL);
  if (!cl_handle) {
      __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to load libLiteRtTopKOpenClSampler.so: %s", dlerror());
  } else {
      __android_log_print(ANDROID_LOG_INFO, kTag, "Successfully loaded libLiteRtTopKOpenClSampler.so globally");
  }

  void* gpu_handle = dlopen("libLiteRtTopKWebGpuSampler.so", RTLD_NOW | RTLD_GLOBAL);
  if (!gpu_handle) {
      __android_log_print(ANDROID_LOG_ERROR, kTag, "Failed to load libLiteRtTopKWebGpuSampler.so: %s", dlerror());
  } else {
      __android_log_print(ANDROID_LOG_INFO, kTag, "Successfully loaded libLiteRtTopKWebGpuSampler.so globally");
  }

  return JNI_VERSION_1_6;
}

