import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../ui/premium_ui.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Processing Queue'),
        actions: [
          Consumer<ProcessingState>(
            builder: (context, state, _) {
              if (state.pendingQueueCount == 0) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                tooltip: 'Clear Queue',
                onPressed: () => _showClearConfirmation(context, state),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: SafeArea(
          child: Consumer<ProcessingState>(
            builder: (context, state, _) {
              final allItems = state.displayQueueItems
                  .map(
                    (item) => _QueueDisplayItem(
                      item: item,
                      isProcessing: item.status == QueueItemStatus.processing,
                    ),
                  )
                  .toList();

              if (allItems.isEmpty) {
                return PremiumEmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'Queue is empty',
                  message:
                      'Share a voice note or import audio to start the next run.',
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _buildQueueSummary(context, state),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: allItems.length,
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final t = Curves.easeOutCubic.transform(
                              animation.value,
                            );
                            return Transform.scale(
                              scale: 0.98 + (t * 0.02),
                              child: child,
                            );
                          },
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        if (state.currentItem != null) {
                          if (oldIndex == 0 || newIndex == 0) {
                            return;
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
      ),
    );
  }

  Widget _buildQueueSummary(BuildContext context, ProcessingState state) {
    final visibleCount = state.queueCount;
    final totalEstimate = state.totalQueueEstimate;

    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.cyan.withAlpha(30),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.cyan.withAlpha(20),
                  AppColors.violet.withAlpha(12),
                ],
              ),
            ),
            child: const Icon(Icons.queue_music_rounded, color: AppColors.cyan),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.currentItem != null
                      ? 'Processing now'
                      : '$visibleCount item${visibleCount == 1 ? '' : 's'} in queue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalEstimate.inSeconds > 0
                      ? 'Estimated ${_formatDuration(totalEstimate)} remaining'
                      : 'Items stay in order and can be rearranged at any time.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(140),
                    fontSize: 13,
                    height: 1.35,
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
                valueColor: AlwaysStoppedAnimation(AppColors.cyan),
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
        padding: const EdgeInsets.only(right: 18),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.red.withAlpha(190), AppColors.red.withAlpha(90)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        state.removeFromQueue(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed: ${item.fileName}'),
            backgroundColor: AppColors.surfaceElevated,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PremiumSurface(
          key: Key('item_$index'),
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(24),
          borderColor: isProcessing
              ? AppColors.cyan.withAlpha(50)
              : Colors.white.withAlpha(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isProcessing
                  ? AppColors.cyan.withAlpha(14)
                  : AppColors.surface.withAlpha(250),
              AppColors.surfaceElevated.withAlpha(255),
            ],
          ),
          child: Row(
            children: [
              if (!isProcessing)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white.withAlpha(80),
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
                      valueColor: AlwaysStoppedAnimation(AppColors.cyan),
                    ),
                  ),
                ),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isProcessing
                      ? AppColors.cyan
                      : Colors.white.withAlpha(44),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(isProcessing ? 255 : 220),
                        fontSize: 14,
                        fontWeight: isProcessing
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isProcessing
                          ? 'Processing now'
                          : 'Estimated ${item.formattedEstimate}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isProcessing)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(110),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context, ProcessingState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Clear Queue?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove all ${state.pendingQueueCount} pending items from the queue?',
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Queue cleared'),
                  backgroundColor: AppColors.surfaceElevated,
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.red)),
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

class _QueueDisplayItem {
  final QueueItem item;
  final bool isProcessing;

  _QueueDisplayItem({required this.item, required this.isProcessing});
}
