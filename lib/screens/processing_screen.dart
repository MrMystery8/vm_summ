import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../ui/premium_ui.dart';
import 'queue_screen.dart';

class ProcessingScreen extends StatelessWidget {
  const ProcessingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Dismiss',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Processing'),
        actions: [
          Consumer<ProcessingState>(
            builder: (context, state, _) {
              final count = state.queueCount;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded),
                    tooltip: 'Queue',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QueueScreen()),
                      );
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 7,
                      top: 8,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: AppColors.cyan,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
              final modelProgress = state.modelStatus == ModelStatus.ready
                  ? 1.0
                  : state.modelDownloadProgress;
              final modelPercent =
                  '${(modelProgress.clamp(0.0, 1.0) * 100).round()}%';
              final processingProgress = state.isProcessing ? state.progress : 0.0;
              final processingPercent =
                  '${(processingProgress.clamp(0.0, 1.0) * 100).round()}%';

              return ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const SizedBox(height: 8),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 40),
                    child: _buildHero(context, state),
                  ),
                  const SizedBox(height: 18),
                  if (state.currentAudioPath != null) ...[
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 100),
                      child: _buildFileCard(state.currentAudioPath!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 140),
                    child: PremiumProgressCard(
                      icon: state.modelStatus == ModelStatus.ready
                          ? Icons.check_rounded
                          : Icons.memory_rounded,
                      accent: state.modelStatus == ModelStatus.ready
                          ? AppColors.green
                          : AppColors.violet,
                      title: state.modelStatus == ModelStatus.ready
                          ? 'Model loaded'
                          : 'Loading model',
                      subtitle: state.modelStatusMessage,
                      valueLabel: modelPercent,
                      progress: modelProgress,
                      footerLeft: state.modelStatus == ModelStatus.ready
                          ? 'Ready for notes'
                          : 'Preparing the model',
                      footerRight: state.modelStatus == ModelStatus.ready
                          ? 'Gemma 4 E2B'
                          : state.modelStatusMessage,
                      action: state.modelStatus == ModelStatus.notDownloaded
                          ? PremiumActionButton(
                              label: 'Download model',
                              icon: Icons.download_rounded,
                              onPressed: () => state.downloadModel(),
                              expanded: true,
                              subtle: true,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 180),
                    child: PremiumProgressCard(
                      icon: state.isProcessing
                          ? Icons.auto_awesome_rounded
                          : Icons.queue_music_rounded,
                      accent: AppColors.cyan,
                      title: state.isProcessing
                          ? 'Processing note'
                          : state.queueCount > 0
                              ? 'Queued notes'
                              : 'Processing idle',
                      subtitle: state.currentAudioPath != null
                          ? state.currentAudioPath!.split('/').last
                          : state.queueCount > 0
                              ? '${state.queueCount} item${state.queueCount == 1 ? '' : 's'} waiting'
                              : 'Waiting for the next note',
                      valueLabel: processingPercent,
                      progress: processingProgress,
                      footerLeft: state.statusMessage.isEmpty
                          ? (state.queueCount > 0 ? 'Ready to process' : 'Idle')
                          : state.statusMessage,
                      footerRight: state.currentAudioPath != null
                          ? 'Current note'
                          : state.queueCount > 0
                              ? 'In queue'
                              : 'No active file',
                      action: state.isProcessing
                          ? PremiumActionButton(
                              label: 'Dismiss',
                              icon: Icons.close_rounded,
                              onPressed: () => Navigator.of(context).maybePop(),
                              expanded: true,
                              subtle: true,
                            )
                          : null,
                    ),
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 220),
                      child: _buildErrorCard(state),
                    ),
                  ],
                  if (state.summaryResult != null) ...[
                    const SizedBox(height: 16),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 260),
                      child: _buildSummaryCard(state),
                    ),
                  ],
                  if (state.transcriptionResult != null) ...[
                    const SizedBox(height: 16),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 300),
                      child: _buildTranscriptCard(state),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, ProcessingState state) {
    final accent = state.isProcessing ? AppColors.cyan : AppColors.violet;
    final subtitle = state.isProcessing
        ? 'Please keep this screen open while we analyze your audio and create a summary.'
        : state.queueCount > 0
            ? 'Files are ready in the queue and will process automatically.'
            : 'This screen shows model loading and note processing progress.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withAlpha(10),
            border: Border.all(color: accent.withAlpha(80), width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withAlpha(60), width: 1.25),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(14),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: accent,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Processing note',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withAlpha(170),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildFileCard(String audioPath) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyan.withAlpha(16),
            ),
            child: const Icon(Icons.audiotrack_rounded, color: AppColors.cyan),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current note',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  audioPath.split('/').last,
                  style: TextStyle(
                    color: Colors.white.withAlpha(140),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ProcessingState state) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      borderColor: AppColors.red.withAlpha(28),
      gradient: LinearGradient(
        colors: [
          AppColors.red.withAlpha(12),
          AppColors.surfaceElevated.withAlpha(255),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.red),
              SizedBox(width: 10),
              Text(
                'Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            state.errorMessage ?? 'Unknown error',
            style: TextStyle(
              color: Colors.white.withAlpha(210),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ProcessingState state) {
    final summary = state.summaryResult!;
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumSectionHeader(
            title: 'Summary',
            subtitle: 'A concise readout of the note.',
          ),
          const SizedBox(height: 14),
          Text(
            summary.summary,
            style: const TextStyle(
              color: Colors.white,
              height: 1.55,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(ProcessingState state) {
    final transcript = state.transcriptionResult!.text;
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumSectionHeader(
            title: 'Transcript',
            subtitle: 'The raw note, preserved for reading and search.',
          ),
          const SizedBox(height: 14),
          Text(
            transcript,
            style: TextStyle(
              color: Colors.white.withAlpha(214),
              height: 1.55,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
