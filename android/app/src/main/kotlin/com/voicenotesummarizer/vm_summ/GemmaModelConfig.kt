package com.voicenotesummarizer.vm_summ

import android.content.Context
import java.io.File

object GemmaModelConfig {
    const val MODELS_DIR = "gemma_models"
    const val BUNDLED_ASSET = "gemma-4-E2B-it.litertlm"
    const val LOCAL_FILENAME = "gemma-4-E2B.litertlm"
    const val CACHE_MARKER_SUFFIX = ".ready"
    const val DISPLAY_NAME = "Gemma 4 E2B"
    const val DESCRIPTION = "Efficient Gemma 4 chat model with audio support"
    const val ESTIMATED_SIZE = "~2.58GB"

    fun modelsDir(context: Context): File = File(context.filesDir, MODELS_DIR)

    fun defaultModelFile(context: Context): File = File(modelsDir(context), LOCAL_FILENAME)
}
