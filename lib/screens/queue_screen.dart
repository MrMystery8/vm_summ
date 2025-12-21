import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/processing_state.dart';

/// Screen for managing the processing queue
/// Allows users to view, reorder, and remove queued items
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Processing Queue',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Consumer<ProcessingState>(
            builder: (context, state, _) {
              if (state.queueCount == 0) return const SizedBox();
              return IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                tooltip: 'Clear Queue',
                onPressed: () => _showClearConfirmation(context, state),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<ProcessingState>(
          builder: (context, state, _) {
            // Show current processing item + queued items
            final allItems = <_QueueDisplayItem>[];

            // Add currently processing item if any
            if (state.currentItem != null) {
              allItems.add(
                _QueueDisplayItem(item: state.currentItem!, isProcessing: true),
              );
            }

            // Add queued items
            for (final item in state.queueItems) {
              allItems.add(_QueueDisplayItem(item: item, isProcessing: false));
            }

            if (allItems.isEmpty) {
              return _buildEmptyState();
            }

            return Column(
              children: [
                // Queue summary
                _buildQueueSummary(state),

                // Queue list
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: allItems.length,
                    onReorder: (oldIndex, newIndex) {
                      // Adjust for currently processing item
                      if (state.currentItem != null) {
                        if (oldIndex == 0 || newIndex == 0) {
                          return; // Can't move processing item
                        }
                        state.reorderQueue(oldIndex - 1, newIndex - 1);
                      } else {
                        state.reorderQueue(oldIndex, newIndex);
                      }
                    },
                    itemBuilder: (context, index) {
                      final displayItem = allItems[index];
                      return _buildQueueItem(
                        context,
                        displayItem,
                        index,
                        state,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 64, color: Colors.white.withAlpha(60)),
          const SizedBox(height: 16),
          Text(
            'Queue is empty',
            style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Share a voice note to start processing',
            style: TextStyle(color: Colors.white.withAlpha(60), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueSummary(ProcessingState state) {
    final pendingCount = state.queueCount;
    final totalEstimate = state.totalQueueEstimate;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D9FF).withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00D9FF).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.queue, color: Color(0xFF00D9FF), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.currentItem != null
                      ? 'Processing...'
                      : '$pendingCount item${pendingCount == 1 ? '' : 's'} in queue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (totalEstimate.inSeconds > 0)
                  Text(
                    'Est. ${_formatDuration(totalEstimate)} remaining',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          if (state.isProcessing)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueItem(
    BuildContext context,
    _QueueDisplayItem displayItem,
    int index,
    ProcessingState state,
  ) {
    final item = displayItem.item;
    final isProcessing = displayItem.isProcessing;

    return Dismissible(
      key: Key(item.id),
      direction: isProcessing
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        state.removeFromQueue(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed: ${item.fileName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        key: Key('item_$index'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isProcessing
              ? const Color(0xFF00D9FF).withAlpha(20)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isProcessing
                ? const Color(0xFF00D9FF).withAlpha(60)
                : Colors.white.withAlpha(15),
          ),
        ),
        child: Row(
          children: [
            // Drag handle (only for non-processing items)
            if (!isProcessing)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.drag_handle,
                    color: Colors.white.withAlpha(60),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF)),
                  ),
                ),
              ),

            // Status indicator
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isProcessing
                    ? const Color(0xFF00D9FF)
                    : Colors.white.withAlpha(40),
              ),
            ),

            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    style: TextStyle(
                      color: Colors.white.withAlpha(isProcessing ? 255 : 200),
                      fontSize: 14,
                      fontWeight: isProcessing
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isProcessing
                        ? 'Processing now...'
                        : 'Est. ${item.formattedEstimate}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(80),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Position badge
            if (!isProcessing)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context, ProcessingState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Clear Queue?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove all ${state.queueCount} pending items from the queue?',
          style: TextStyle(color: Colors.white.withAlpha(180)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
          ),
          TextButton(
            onPressed: () {
              state.clearQueue();
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Queue cleared')));
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}

/// Helper class for displaying queue items
class _QueueDisplayItem {
  final QueueItem item;
  final bool isProcessing;

  _QueueDisplayItem({required this.item, required this.isProcessing});
}
