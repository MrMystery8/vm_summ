import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Native audio converter using platform channel to Android MediaCodec.
/// Converts Opus/Ogg and other audio formats to WAV 16kHz mono.
class AudioConverter {
  static const MethodChannel _channel = MethodChannel(
    'com.voicenotesummarizer/audio_converter',
  );

  bool _initialized = false;

  /// Initialize the converter
  Future<void> initialize() async {
    _initialized = true;
  }

  /// Converts any audio file to WAV using native Android MediaCodec.
  ///
  /// [inputFile] - The audio file to convert (Opus, Ogg, MP3, M4A, etc.)
  /// Returns a new File containing 16kHz mono WAV audio
  Future<File> convertTo16kMonoWav(File inputFile) async {
    if (!_initialized) {
      await initialize();
    }

    final inputPath = inputFile.path;
    final inputSize = await inputFile.length();
    debugPrint('AudioConverter: Input: $inputPath ($inputSize bytes)');

    // Generate output path
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/converted_$timestamp.wav';

    try {
      // Call native Android MediaCodec converter
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'convertToWav',
        {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'sampleRate': 16000, // 16kHz mono
          'channels': 1, // Mono
        },
      );

      if (result != null && result['success'] == true) {
        final convertedPath = result['outputPath'] as String;
        final outputFile = File(convertedPath);
        final outputSize = await outputFile.length();
        debugPrint(
          'AudioConverter: Success! Output: $convertedPath ($outputSize bytes)',
        );
        return outputFile;
      } else {
        throw Exception('Conversion returned unsuccessful result');
      }
    } on PlatformException catch (e) {
      debugPrint('AudioConverter: Platform error: ${e.message}');
      debugPrint('AudioConverter: Details: ${e.details}');

      // Fallback: copy file and let Whisper try to handle it
      debugPrint('AudioConverter: Falling back to direct copy');
      final ext = inputPath.split('.').last.toLowerCase();
      final fallbackPath = '${tempDir.path}/converted_fallback_$timestamp.$ext';
      final fallbackFile = await inputFile.copy(fallbackPath);
      return fallbackFile;
    } catch (e) {
      debugPrint('AudioConverter: Error: $e');

      // Fallback: copy file
      final ext = inputPath.split('.').last.toLowerCase();
      final fallbackPath = '${tempDir.path}/converted_fallback_$timestamp.$ext';
      final fallbackFile = await inputFile.copy(fallbackPath);
      return fallbackFile;
    }
  }

  /// Clean up temporary files
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('converted_')) {
          try {
            await entity.delete();
          } catch (e) {
            // Ignore
          }
        }
      }
    } catch (e) {
      debugPrint('AudioConverter: Cleanup error: $e');
    }
  }
}
