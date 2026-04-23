import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../ui/premium_ui.dart';
import '../utils/slider_bounds.dart';
import 'queue_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _togglePlay(String? audioPath) async {
    if (audioPath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(audioPath));
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Processing'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.read<ProcessingState>().clear(),
        ),
        actions: [
          Consumer<ProcessingState>(
            builder: (context, state, _) {
              final queueCount = state.queueCount;
              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.queue_music_rounded),
                    if (queueCount > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.cyan,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$queueCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'View Queue',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const QueueScreen(),
                    ),
                  );
                },
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
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 70),
                      child: _buildModelStatusCard(state),
                    ),
                    const SizedBox(height: 16),
                    if (state.currentAudioPath != null) ...[
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 130),
                        child: _buildAudioPlayerCard(state.currentAudioPath!),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 190),
                      child: _buildProcessingSteps(state),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 240),
                        child: _buildErrorCard(state),
                      ),
                    ],
                    if (state.transcriptionResult != null) ...[
                      const SizedBox(height: 16),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 280),
                        child: _buildTranscriptCard(state),
                      ),
                    ],
                    if (state.summaryResult != null) ...[
                      const SizedBox(height: 16),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 320),
                        child: _buildSummaryCard(state),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModelStatusCard(ProcessingState state) {
    final isReady = state.modelStatus == ModelStatus.ready;
    final isCopying = state.modelStatus == ModelStatus.copying;
    final accent = isReady ? AppColors.green : AppColors.cyan;

    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: accent.withAlpha(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(18),
                ),
                child: Icon(
                  isReady ? Icons.check_rounded : Icons.memory_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gemma model',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.modelStatusMessage,
                      style: TextStyle(
                        color: Colors.white.withAlpha(145),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.modelStatus == ModelStatus.notDownloaded)
                PremiumPill(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  color: accent,
                )
              else if (isCopying)
                const PremiumPill(
                  icon: Icons.downloading_rounded,
                  label: 'Syncing',
                  color: AppColors.amber,
                )
              else
                const PremiumPill(
                  icon: Icons.check_rounded,
                  label: 'Ready',
                  color: AppColors.green,
                ),
            ],
          ),
          if (state.modelStatus == ModelStatus.notDownloaded) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => state.downloadModel(),
                child: const Text('Download Model'),
              ),
            ),
          ],
          if (isCopying) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: state.modelDownloadProgress,
                minHeight: 8,
                backgroundColor: Colors.white.withAlpha(20),
                valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(state.modelDownloadProgress * 100).toInt()}%',
              style: TextStyle(
                color: Colors.white.withAlpha(120),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioPlayerCard(String audioPath) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.cyan.withAlpha(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withAlpha(18),
                ),
                child: IconButton(
                  onPressed: () => _togglePlay(audioPath),
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice note',
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
                        color: Colors.white.withAlpha(130),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PremiumPill(
                icon: Icons.timelapse_rounded,
                label: _formatDuration(_duration),
                color: AppColors.cyan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: clampSliderValue(
                _position.inMilliseconds.toDouble(),
                sliderMaxFromDuration(_duration),
              ),
              max: sliderMaxFromDuration(_duration),
              onChanged: (value) {
                _audioPlayer.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingSteps(ProcessingState state) {
    final steps = [
      _StepData(
        'Converting Audio',
        ProcessingStatus.convertingAudio,
        Icons.transform_rounded,
      ),
      _StepData(
        'Initializing Gemma',
        ProcessingStatus.initializingModel,
        Icons.memory_rounded,
      ),
      _StepData(
        'Processing Audio',
        ProcessingStatus.processing,
        Icons.auto_awesome_rounded,
      ),
    ];

    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Processing steps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...steps.map((step) {
            final isComplete = _isStepComplete(state.status, step.status);
            final isActive = state.status == step.status;
            final isFailed = state.status == ProcessingStatus.error;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComplete
                          ? AppColors.green
                          : isActive
                          ? AppColors.cyan
                          : isFailed
                          ? AppColors.red.withAlpha(40)
                          : Colors.white.withAlpha(18),
                    ),
                    child: isActive
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Icon(
                            isComplete ? Icons.check_rounded : step.icon,
                            color: isComplete || isActive
                                ? Colors.white
                                : Colors.white.withAlpha(90),
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        color: isComplete || isActive
                            ? Colors.white
                            : Colors.white.withAlpha(90),
                        fontSize: 15,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ProcessingState state) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.red.withAlpha(36),
      gradient: LinearGradient(
        colors: [
          AppColors.red.withAlpha(18),
          AppColors.surfaceElevated.withAlpha(255),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.red),
              const SizedBox(width: 12),
              const Text(
                'Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.errorMessage ?? 'Unknown error',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => state.clear(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(ProcessingState state) {
    final transcript = state.transcriptionResult?.text ?? '';

    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transcript',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${transcript.split(' ').where((w) => w.isNotEmpty).length} words',
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Text(
            transcript,
            style: TextStyle(
              color: Colors.white.withAlpha(210),
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ProcessingState state) {
    final summary = state.summaryResult!;

    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.cyan.withAlpha(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            summary.summary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  bool _isStepComplete(ProcessingStatus current, ProcessingStatus step) {
    return current.index > step.index;
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}

class _StepData {
  final String label;
  final ProcessingStatus status;
  final IconData icon;

  _StepData(this.label, this.status, this.icon);
}
