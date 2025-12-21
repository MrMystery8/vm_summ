import 'dart:io';
import 'package:share_handler/share_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Handles receiving shared files from other apps (e.g., WhatsApp)
///
/// Supports both initial share (app launch) and runtime share events
class ShareHandlerService {
  final ShareHandlerPlatform _shareHandler = ShareHandlerPlatform.instance;

  /// Callback for when a file is shared to the app
  Function(File audioFile)? onFileReceived;

  /// Initialize the share handler and start listening for shares
  Future<void> initialize() async {
    // Check for initial shared content (app launched via share)
    await _checkInitialShare();

    // Listen for shares while app is running
    _shareHandler.sharedMediaStream.listen(_handleSharedMedia);
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

      // Check if it's an audio file
      if (_isAudioFile(attachment.path)) {
        final file = File(attachment.path);
        if (await file.exists()) {
          // Copy to app's documents directory for safety
          final savedFile = await _saveToDocuments(file);
          onFileReceived?.call(savedFile);
        }
      }
    }
  }

  /// Check if file is an audio file we can process
  bool _isAudioFile(String path) {
    final lowercasePath = path.toLowerCase();
    return lowercasePath.endsWith('.ogg') ||
        lowercasePath.endsWith('.opus') ||
        lowercasePath.endsWith('.m4a') ||
        lowercasePath.endsWith('.mp3') ||
        lowercasePath.endsWith('.wav') ||
        lowercasePath.endsWith('.aac');
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
    onFileReceived = null;
  }
}
