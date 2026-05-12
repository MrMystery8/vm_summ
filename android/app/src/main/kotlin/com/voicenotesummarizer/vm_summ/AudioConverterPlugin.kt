package com.voicenotesummarizer.vm_summ

import android.media.*
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.io.BufferedOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Native Android audio converter using MediaCodec.
 * Converts Opus/Ogg and other audio formats to WAV 16kHz mono.
 */
class AudioConverterPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.voicenotesummarizer/audio_converter")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "convertToWav" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                val channels = call.argument<Int>("channels") ?: 1
                
                if (inputPath == null || outputPath == null) {
                    result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
                    return
                }
                
                Thread {
                    try {
                        val success = convertAudioToWav(inputPath, outputPath, sampleRate, channels)
                        if (success) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.success(mapOf("success" to true, "outputPath" to outputPath))
                            }
                        } else {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.error("CONVERSION_FAILED", "Audio conversion failed", null)
                            }
                        }
                    } catch (e: Exception) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.error("CONVERSION_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * Convert audio file to WAV format using MediaExtractor and MediaCodec.
     */
    private fun convertAudioToWav(
        inputPath: String,
        outputPath: String,
        targetSampleRate: Int,
        targetChannels: Int
    ): Boolean {
        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            throw Exception("Input file does not exist: $inputPath")
        }

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            try {
                extractor.setDataSource(inputPath)
            } catch (e: Exception) {
                throw Exception("Failed to open input file: ${e.message}")
            }

            var audioTrackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    inputFormat = format
                    break
                }
            }

            if (audioTrackIndex < 0 || inputFormat == null) {
                throw Exception("No audio track found in file")
            }

            extractor.selectTrack(audioTrackIndex)

            val inputMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "audio/raw"
            val inputSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val inputChannels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            decoder = MediaCodec.createDecoderByType(inputMime)
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()

            val tmpPcmFile = File.createTempFile("decoded_pcm_", ".raw", inputFile.parentFile)
            var totalBytes = 0L
            val pcmOut = BufferedOutputStream(FileOutputStream(tmpPcmFile))

            val timeoutUs = 10000L
            var isEos = false
            val bufferInfo = MediaCodec.BufferInfo()

            try {
                while (!isEos) {
                    val inputBufferIndex = decoder.dequeueInputBuffer(timeoutUs)
                    if (inputBufferIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                        if (inputBuffer != null) {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inputBufferIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                            } else {
                                decoder.queueInputBuffer(
                                    inputBufferIndex, 0, sampleSize,
                                    extractor.sampleTime, 0
                                )
                                extractor.advance()
                            }
                        }
                    }

                    val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                    when {
                        outputBufferIndex >= 0 -> {
                            val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                            if (outputBuffer != null && bufferInfo.size > 0) {
                                outputBuffer.position(bufferInfo.offset)
                                outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                                val chunk = ByteArray(bufferInfo.size)
                                outputBuffer.get(chunk)
                                pcmOut.write(chunk)
                                totalBytes += chunk.size.toLong()
                            }
                            decoder.releaseOutputBuffer(outputBufferIndex, false)

                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                isEos = true
                            }
                        }
                        outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ||
                            outputBufferIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    }
                }
            } finally {
                pcmOut.flush()
                pcmOut.close()
            }

            if (totalBytes == 0L) {
                throw Exception("No audio data decoded")
            }

            if (inputSampleRate != targetSampleRate || inputChannels != targetChannels) {
                val allPcm = tmpPcmFile.readBytes()
                val resampledData = resamplePcm(
                    allPcm,
                    inputSampleRate,
                    inputChannels,
                    targetSampleRate,
                    targetChannels,
                )
                writeWavFile(outputPath, resampledData, targetSampleRate, targetChannels)
            } else {
                writeWavFromPcmFile(
                    outputPath = outputPath,
                    pcmFile = tmpPcmFile,
                    pcmSize = totalBytes,
                    sampleRate = targetSampleRate,
                    channels = targetChannels,
                )
            }
            tmpPcmFile.delete()

            return true
        } finally {
            decoder?.runCatching { stop() }
            decoder?.runCatching { release() }
            extractor.release()
        }
    }

    /**
     * Simple linear resampling (good enough for speech).
     */
    private fun resamplePcm(
        input: ByteArray,
        srcRate: Int,
        srcChannels: Int,
        dstRate: Int,
        dstChannels: Int
    ): ByteArray {
        val bytesPerSample = 2 // 16-bit audio
        val srcSamplesPerFrame = srcChannels
        val srcBytesPerFrame = srcSamplesPerFrame * bytesPerSample
        val srcFrameCount = input.size / srcBytesPerFrame

        val ratio = srcRate.toDouble() / dstRate.toDouble()
        val dstFrameCount = (srcFrameCount / ratio).toInt()
        val dstBytesPerFrame = dstChannels * bytesPerSample
        val output = ByteArray(dstFrameCount * dstBytesPerFrame)

        val srcBuffer = ByteBuffer.wrap(input).order(ByteOrder.LITTLE_ENDIAN)
        val dstBuffer = ByteBuffer.wrap(output).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until dstFrameCount) {
            val srcPos = (i * ratio).toInt().coerceIn(0, srcFrameCount - 1)
            srcBuffer.position(srcPos * srcBytesPerFrame)

            // Read source sample(s)
            val leftSample = if (srcChannels >= 1) srcBuffer.short else 0
            val rightSample = if (srcChannels >= 2) srcBuffer.short else leftSample

            // Write to destination
            if (dstChannels == 1) {
                // Mono: average channels
                val monoSample = ((leftSample + rightSample) / 2).toShort()
                dstBuffer.putShort(monoSample)
            } else {
                dstBuffer.putShort(leftSample)
                if (dstChannels >= 2) {
                    dstBuffer.putShort(rightSample)
                }
            }
        }

        return output
    }

    /**
     * Write PCM data to WAV file with proper header.
     */
    private fun writeWavFile(
        path: String,
        pcmData: ByteArray,
        sampleRate: Int,
        channels: Int
    ) {
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8

        val fos = FileOutputStream(path)
        val buffer = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)

        // RIFF header
        buffer.put("RIFF".toByteArray())
        buffer.putInt(36 + pcmData.size)  // File size - 8
        buffer.put("WAVE".toByteArray())

        // fmt chunk
        buffer.put("fmt ".toByteArray())
        buffer.putInt(16)  // Subchunk1 size
        buffer.putShort(1)  // Audio format (PCM)
        buffer.putShort(channels.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())

        // data chunk
        buffer.put("data".toByteArray())
        buffer.putInt(pcmData.size)

        fos.write(buffer.array())
        fos.write(pcmData)
        fos.close()
    }

    private fun writeWavFromPcmFile(
        outputPath: String,
        pcmFile: File,
        pcmSize: Long,
        sampleRate: Int,
        channels: Int
    ) {
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8

        FileOutputStream(outputPath).use { fos ->
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray())
            header.putInt(36 + pcmSize.toInt())
            header.put("WAVE".toByteArray())
            header.put("fmt ".toByteArray())
            header.putInt(16)
            header.putShort(1)
            header.putShort(channels.toShort())
            header.putInt(sampleRate)
            header.putInt(byteRate)
            header.putShort(blockAlign.toShort())
            header.putShort(bitsPerSample.toShort())
            header.put("data".toByteArray())
            header.putInt(pcmSize.toInt())
            fos.write(header.array())
            pcmFile.inputStream().use { input -> input.copyTo(fos) }
        }
    }
}
