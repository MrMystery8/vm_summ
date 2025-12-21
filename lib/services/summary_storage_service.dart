import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A record of a processed voice note with all metadata
class SummaryRecord {
  final String id;
  final DateTime createdAt;
  final String sourceFileName;
  final String? sourceFilePath;

  final String transcript;
  final String summary;
  final List<String> keyPoints;
  final String actionItems;
  final int transcriptLength;
  final int audioDurationSeconds;

  SummaryRecord({
    required this.id,
    required this.createdAt,
    required this.sourceFileName,
    this.sourceFilePath,

    required this.transcript,
    required this.summary,
    required this.keyPoints,
    required this.actionItems,
    this.transcriptLength = 0,
    this.audioDurationSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'sourceFileName': sourceFileName,
    'sourceFilePath': sourceFilePath,

    'transcript': transcript,
    'summary': summary,
    'keyPoints': keyPoints,
    'actionItems': actionItems,
    'transcriptLength': transcriptLength,
    'audioDurationSeconds': audioDurationSeconds,
  };

  factory SummaryRecord.fromJson(Map<String, dynamic> json) {
    return SummaryRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sourceFileName: json['sourceFileName'] as String,
      sourceFilePath: json['sourceFilePath'] as String?,

      transcript: json['transcript'] as String,
      summary: json['summary'] as String,
      keyPoints: List<String>.from(json['keyPoints'] as List),
      actionItems: json['actionItems'] as String,
      transcriptLength: json['transcriptLength'] as int? ?? 0,
      audioDurationSeconds: json['audioDurationSeconds'] as int? ?? 0,
    );
  }

  /// Get a short preview of the transcript
  String get transcriptPreview {
    if (transcript.length <= 100) return transcript;
    return '${transcript.substring(0, 100)}...';
  }

  /// Get formatted date string
  String get formattedDate {
    return '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}';
  }
}

/// Service for persisting and retrieving summary records
class SummaryStorageService {
  static const String _storageFileName = 'summary_history.json';
  List<SummaryRecord> _records = [];
  bool _initialized = false;

  /// Initialize the storage service by loading existing records
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);
        _records = jsonList
            .map((item) => SummaryRecord.fromJson(item as Map<String, dynamic>))
            .toList();
        // Sort by date, newest first
        _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        debugPrint('SummaryStorage: Loaded ${_records.length} records');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('SummaryStorage: Error loading records: $e');
      _records = [];
      _initialized = true;
    }
  }

  /// Save a new summary record
  Future<SummaryRecord> saveRecord({
    required String sourceFileName,
    String? sourceFilePath,
    required String transcript,
    required String summary,
    required List<String> keyPoints,
    required String actionItems,
    int audioDurationSeconds = 0,
  }) async {
    await initialize();

    final record = SummaryRecord(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      sourceFileName: sourceFileName,
      sourceFilePath: sourceFilePath,

      transcript: transcript,
      summary: summary,
      keyPoints: keyPoints,
      actionItems: actionItems,
      transcriptLength: transcript.length,
      audioDurationSeconds: audioDurationSeconds,
    );

    _records.insert(0, record); // Add to beginning (newest first)
    await _saveToFile();

    debugPrint('SummaryStorage: Saved record ${record.id}');
    return record;
  }

  /// Get all stored records
  Future<List<SummaryRecord>> getAllRecords() async {
    await initialize();
    return List.unmodifiable(_records);
  }

  /// Get a specific record by ID
  Future<SummaryRecord?> getRecord(String id) async {
    await initialize();
    try {
      return _records.firstWhere((r) => r.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Delete a record by ID
  Future<bool> deleteRecord(String id) async {
    await initialize();
    final index = _records.indexWhere((r) => r.id == id);
    if (index == -1) return false;

    _records.removeAt(index);
    await _saveToFile();
    debugPrint('SummaryStorage: Deleted record $id');
    return true;
  }

  /// Get the number of stored records
  int get recordCount => _records.length;

  /// Clear all records
  Future<void> clearAll() async {
    _records.clear();
    await _saveToFile();
    debugPrint('SummaryStorage: Cleared all records');
  }

  Future<File> _getStorageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_storageFileName');
  }

  Future<void> _saveToFile() async {
    try {
      final file = await _getStorageFile();
      final jsonList = _records.map((r) => r.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      debugPrint('SummaryStorage: Error saving records: $e');
    }
  }
}
