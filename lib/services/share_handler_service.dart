import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_handler/share_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_converter.dart';

/// Handles receiving shared files from other apps (e.g., WhatsApp)
///
/// Supports both initial share (app launch) and runtime share events
class SharedAudioAttachmentDecision {
  final bool accepted;
  final String reason;

  const SharedAudioAttachmentDecision({
    required this.accepted,
    required this.reason,
  });
}

/// Pure helper used to decide whether a shared attachment should be treated as audio.
SharedAudioAttachmentDecision assessSharedAudioAttachment(
  SharedAttachment attachment,
) {
  final path = attachment.path.trim();
  if (path.isEmpty) {
    return const SharedAudioAttachmentDecision(
      accepted: false,
      reason: 'attachment path was empty',
    );
  }

  if (attachment.type == SharedAttachmentType.audio) {
    return const SharedAudioAttachmentDecision(
      accepted: true,
      reason: 'attachment was marked as audio',
    );
  }

  if (AudioConverter.isSupportedInputPath(path)) {
    return const SharedAudioAttachmentDecision(
      accepted: true,
      reason: 'attachment path matched a supported audio extension',
    );
  }

  return SharedAudioAttachmentDecision(
    accepted: false,
    reason:
        'unsupported attachment type ${attachment.type.name} with path $path',
  );
}

class ShareHandlerService {
  final ShareHandlerPlatform _shareHandler = ShareHandlerPlatform.instance;

  /// Callback for when a file is shared to the app
  Function(File audioFile)? onFileReceived;
  StreamSubscription<SharedMedia>? _shareSubscription;
  bool _initialized = false;

  /// Initialize the share handler and start listening for shares
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    // Listen first so we don't miss a runtime share that races the cold-start check.
    _shareSubscription ??= _shareHandler.sharedMediaStream.listen(
      _handleSharedMedia,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('ShareHandler: stream error: $error');
      },
    );

    // Check for initial shared content (app launched via share)
    await _checkInitialShare();
  }

  /// Check if app was launched with shared content
  Future<void> _checkInitialShare() async {
    final initialMedia = await _shareHandler.getInitialSharedMedia();
    if (initialMedia != null) {
      await _handleSharedMedia(initialMedia);
    }
  }

  /// Process shared media
  Future<void> _handleSharedMedia(SharedMedia media) async {
    if (media.attachments == null || media.attachments!.isEmpty) return;

    for (final attachment in media.attachments!) {
      if (attachment == null) continue;

      final decision = assessSharedAudioAttachment(attachment);
      if (!decision.accepted) {
        debugPrint(
          'ShareHandler: Rejecting ${attachment.path} (${decision.reason})',
        );
        continue;
      }

      final file = File(attachment.path);
      if (await file.exists()) {
        try {
          // Copy to app's documents directory for safety
          final savedFile = await _saveToDocuments(file);
          onFileReceived?.call(savedFile);
        } catch (e) {
          debugPrint('ShareHandler: Failed to save ${attachment.path}: $e');
        }
      } else {
        debugPrint(
          'ShareHandler: Shared file missing on disk after acceptance: ${attachment.path}',
        );
      }
    }
  }

  /// Check if file is an audio file we can process
  bool _isAudioFile(String path) {
    return AudioConverter.isSupportedInputPath(path);
  }

  /// Save shared file to documents directory
  Future<File> _saveToDocuments(File sourceFile) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final voiceNotesDir = Directory('${docsDir.path}/voice_notes');

    if (!await voiceNotesDir.exists()) {
      await voiceNotesDir.create(recursive: true);
    }

    final fileName =
        'voice_note_${DateTime.now().millisecondsSinceEpoch}${_getExtension(sourceFile.path)}';
    final destPath = '${voiceNotesDir.path}/$fileName';

    return await sourceFile.copy(destPath);
  }

  String _getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    return lastDot >= 0 ? path.substring(lastDot) : '.ogg';
  }

  /// Reset the share handler state
  Future<void> reset() async {
    await _shareHandler.resetInitialSharedMedia();
  }

  void dispose() {
    _shareSubscription?.cancel();
    _shareSubscription = null;
    _initialized = false;
    onFileReceived = null;
  }
}
