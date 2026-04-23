import 'package:flutter/widgets.dart';

import '../screens/history_screen.dart';
import '../screens/note_detail_screen.dart';
import '../services/summary_storage_service.dart';

Widget notificationDestinationForRecord(SummaryRecord record) {
  return NoteDetailScreen(record: record);
}

Widget notificationFallbackDestination() {
  return const HistoryScreen();
}
