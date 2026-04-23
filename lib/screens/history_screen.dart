import 'package:flutter/material.dart';

import '../services/summary_storage_service.dart';
import '../ui/premium_ui.dart';
import 'note_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SummaryStorageService _storageService = SummaryStorageService();
  final TextEditingController _searchController = TextEditingController();
  List<SummaryRecord> _records = [];
  List<SummaryRecord> _filteredRecords = [];
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final records = await _storageService.getAllRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      _filteredRecords = records;
      _isLoading = false;
    });
  }

  void _filterRecords(String query) {
    if (query.isEmpty) {
      setState(() => _filteredRecords = _records);
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredRecords = _records.where((record) {
        return record.sourceFileName.toLowerCase().contains(lowerQuery) ||
            record.summary.toLowerCase().contains(lowerQuery) ||
            record.transcript.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
                  border: InputBorder.none,
                ),
                onChanged: _filterRecords,
              )
            : const Text('History'),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _filterRecords('');
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (_records.isNotEmpty && !_isSearching)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear all history',
              onPressed: _confirmClearAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              )
            : _records.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.history_rounded,
                title: 'No summaries yet',
                message:
                    'Process a voice note to see it appear in your archive.',
              )
            : _filteredRecords.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching notes',
                message:
                    'Try a different file name, summary phrase, or transcript word.',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _filteredRecords.length,
                itemBuilder: (context, index) {
                  final record = _filteredRecords[index];
                  return AnimatedEntrance(
                    delay: Duration(milliseconds: 30 * index),
                    child: _buildRecordCard(record),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildRecordCard(SummaryRecord record) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumSurface(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(record: record),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.cyan.withAlpha(20),
                        AppColors.violet.withAlpha(14),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.article_outlined,
                    color: AppColors.cyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.sourceFileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.formattedDate,
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.red.withAlpha(210),
                  ),
                  onPressed: () => _confirmDelete(record),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              record.summary.isEmpty
                  ? record.transcriptPreview
                  : record.summary,
              style: TextStyle(
                color: Colors.white.withAlpha(210),
                fontSize: 14,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PremiumPill(
                  icon: Icons.text_fields_rounded,
                  label: '${record.transcriptLength} chars',
                  color: AppColors.cyan,
                ),
                PremiumPill(
                  icon: Icons.schedule_rounded,
                  label: record.formattedDate.split(' ').first,
                  color: AppColors.violet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(SummaryRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Delete record?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${record.sourceFileName}"? This cannot be undone.',
          style: TextStyle(color: Colors.white.withAlpha(180)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storageService.deleteRecord(record.id);
              _loadRecords();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Clear all history?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete all ${_records.length} records? This cannot be undone.',
          style: TextStyle(color: Colors.white.withAlpha(180)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storageService.clearAll();
              _loadRecords();
            },
            child: const Text(
              'Clear all',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
