cmake_minimum_required(VERSION 3.22.1)

project(litert_sampler_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(litert_sampler_bridge SHARED litert_sampler_bridge.cpp)
target_link_libraries(litert_sampler_bridge PRIVATE log)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    file(GLOB LITERTLM_AAR_FILES
        "$ENV{HOME}/.gradle/caches/modules-2/files-2.1/com.google.ai.edge.litertlm/litertlm-android/0.11.0/*/litertlm-android-0.11.0.aar")
    list(SORT LITERTLM_AAR_FILES)
    list(LENGTH LITERTLM_AAR_FILES LITERTLM_AAR_COUNT)
    if(LITERTLM_AAR_COUNT EQUAL 0)
        message(FATAL_ERROR "Could not find litertlm-android-0.11.0.aar in the local Gradle cache")
    endif()
    list(GET LITERTLM_AAR_FILES 0 LITERTLM_AAR_PATH)

    set(EXTRACT_DIR "${CMAKE_CURRENT_BINARY_DIR}/litertlm_aar")
    file(MAKE_DIRECTORY "${EXTRACT_DIR}")
    file(ARCHIVE_EXTRACT INPUT "${LITERTLM_AAR_PATH}" DESTINATION "${EXTRACT_DIR}")

    set(LITERT_CORE_SO "${EXTRACT_DIR}/jni/arm64-v8a/libLiteRt.so")
    set(OPENCL_SAMPLER_SO "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/arm64-v8a/libLiteRtTopKOpenClSampler.so")
    set(WEBGPU_SAMPLER_SO "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/arm64-v8a/libLiteRtTopKWebGpuSampler.so")

    if(NOT EXISTS "${LITERT_CORE_SO}")
        message(FATAL_ERROR "Missing extracted core LiteRT shared object: ${LITERT_CORE_SO}")
    endif()
    if(NOT EXISTS "${OPENCL_SAMPLER_SO}")
        message(FATAL_ERROR "Missing packaged OpenCL sampler shared object: ${OPENCL_SAMPLER_SO}")
    endif()
    if(NOT EXISTS "${WEBGPU_SAMPLER_SO}")
        message(FATAL_ERROR "Missing packaged WebGpu sampler shared object: ${WEBGPU_SAMPLER_SO}")
    endif()

    add_library(litert_core SHARED IMPORTED GLOBAL)
    set_target_properties(litert_core PROPERTIES IMPORTED_LOCATION "${LITERT_CORE_SO}")

    add_library(litert_opencl_sampler SHARED IMPORTED GLOBAL)
    set_target_properties(litert_opencl_sampler PROPERTIES IMPORTED_LOCATION "${OPENCL_SAMPLER_SO}")

    add_library(litert_webgpu_sampler SHARED IMPORTED GLOBAL)
    set_target_properties(litert_webgpu_sampler PROPERTIES IMPORTED_LOCATION "${WEBGPU_SAMPLER_SO}")

    target_link_libraries(litert_sampler_bridge PRIVATE litert_core litert_opencl_sampler litert_webgpu_sampler)
endif()
