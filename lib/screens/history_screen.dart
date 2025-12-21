import 'package:flutter/material.dart';
import '../services/summary_storage_service.dart';

/// Screen to view history of processed voice notes
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SummaryStorageService _storageService = SummaryStorageService();
  List<SummaryRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _storageService.getAllRecords();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_records.isNotEmpty)
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
          : _buildHistoryList(),
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
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
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
        onTap: () => _showRecordDetail(record),
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

  void _showRecordDetail(SummaryRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.sourceFileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
              const SizedBox(height: 16),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildSection('Summary', record.summary),
                    _buildSection(
                      'Key Points',
                      record.keyPoints.map((p) => '• $p').join('\n'),
                    ),
                    _buildSection('Action Items', record.actionItems),
                    _buildSection('Full Transcript', record.transcript),
                    const SizedBox(height: 20),
                    // Metadata
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Metadata',
                            style: TextStyle(
                              color: Colors.white.withAlpha(100),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Transcript Length: ${record.transcriptLength} characters',
                            style: TextStyle(
                              color: Colors.white.withAlpha(80),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    if (content.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF00D9FF),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 14),
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
