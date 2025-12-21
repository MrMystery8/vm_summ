import 'package:flutter/material.dart';
import '../services/summary_storage_service.dart';
import 'note_detail_screen.dart';

/// Screen to view history of processed voice notes
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SummaryStorageService _storageService = SummaryStorageService();
  List<SummaryRecord> _records = [];
  List<SummaryRecord> _filteredRecords = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _storageService.getAllRecords();
    setState(() {
      _records = records;
      _filteredRecords = records;
      _isLoading = false;
    });
  }

  void _filterRecords(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredRecords = _records;
      });
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
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                onChanged: _filterRecords,
              )
            : const Text(
                'History',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
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
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmClearAll,
              tooltip: 'Clear all history',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
            )
          : _records.isEmpty
          ? _buildEmptyState()
          : _filteredRecords.isEmpty
          ? _buildNoSearchResults()
          : _buildHistoryList(),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.white.withAlpha(50)),
          const SizedBox(height: 16),
          Text(
            'No matching notes found',
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.white.withAlpha(50)),
          const SizedBox(height: 16),
          Text(
            'No summaries yet',
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Process a voice note to see it here',
            style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredRecords.length,
      itemBuilder: (context, index) {
        final record = _filteredRecords[index];
        return _buildRecordCard(record);
      },
    );
  }

  Widget _buildRecordCard(SummaryRecord record) {
    return Card(
      color: const Color(0xFF1A1A2E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(record: record),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D9FF).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.article_outlined,
                      color: Color(0xFF00D9FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.sourceFileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          record.formattedDate,
                          style: TextStyle(
                            color: Colors.white.withAlpha(100),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.withAlpha(180),
                    ),
                    onPressed: () => _confirmDelete(record),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Summary preview
              Text(
                record.summary.isEmpty
                    ? record.transcriptPreview
                    : record.summary,
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 13,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              // Model chips
              Wrap(
                spacing: 8,
                children: [
                  _buildChip(
                    '${record.transcriptLength} chars',
                    Icons.text_fields,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withAlpha(120)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SummaryRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Delete Record?',
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Clear All History?',
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
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
