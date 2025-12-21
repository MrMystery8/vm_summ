import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/processing_state.dart';
import 'queue_screen.dart';

/// Enhanced processing screen with audio player and model status
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
      setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
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
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(audioPath));
      setState(() => _isPlaying = true);
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
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Processing', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            context.read<ProcessingState>().clear();
          },
        ),
        actions: [
          // Queue button with badge
          Consumer<ProcessingState>(
            builder: (context, state, _) {
              final queueCount = state.queueCount;
              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.queue_music, color: Colors.white),
                    if (queueCount > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00D9FF),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$queueCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
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
        ],
      ),
      body: SafeArea(
        child: Consumer<ProcessingState>(
          builder: (context, state, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Model status card
                _buildModelStatusCard(state),
                const SizedBox(height: 20),

                // Audio player card (if file available)
                if (state.currentAudioPath != null)
                  _buildAudioPlayerCard(state.currentAudioPath!),

                const SizedBox(height: 20),

                // Processing steps
                _buildProcessingSteps(state),

                const SizedBox(height: 20),

                // Error display
                if (state.errorMessage != null) _buildErrorCard(state),

                // Transcript display (if available)
                if (state.transcriptionResult != null)
                  _buildTranscriptCard(state),

                // Summary display (if available)
                if (state.summaryResult != null) _buildSummaryCard(state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelStatusCard(ProcessingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                state.modelStatus == ModelStatus.ready
                    ? Icons.check_circle
                    : state.modelStatus == ModelStatus.copying
                    ? Icons.downloading
                    : Icons.warning,
                color: state.modelStatus == ModelStatus.ready
                    ? Colors.green
                    : state.modelStatus == ModelStatus.copying
                    ? Colors.orange
                    : Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gemma 3n Model',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      state.modelStatusMessage,
                      style: TextStyle(
                        color: Colors.white.withAlpha(180),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.modelStatus == ModelStatus.notDownloaded)
                ElevatedButton(
                  onPressed: () => state.downloadModel(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Download'),
                ),
            ],
          ),
          if (state.modelStatus == ModelStatus.copying) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.modelDownloadProgress,
              backgroundColor: Colors.white.withAlpha(30),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF00D9FF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(state.modelDownloadProgress * 100).toInt()}%',
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioPlayerCard(String audioPath) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00D9FF).withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D9FF).withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.audio_file, color: Color(0xFF00D9FF), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice Note',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      audioPath.split('/').last,
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Play/Pause button
              IconButton(
                onPressed: () => _togglePlay(audioPath),
                icon: Icon(
                  _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: const Color(0xFF00D9FF),
                  size: 48,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _position.inMilliseconds.toDouble(),
              max: _duration.inMilliseconds.toDouble().clamp(
                1,
                double.infinity,
              ),
              activeColor: const Color(0xFF00D9FF),
              inactiveColor: Colors.white.withAlpha(30),
              onChanged: (value) {
                _audioPlayer.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          // Time display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 12,
                ),
              ),
            ],
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
        Icons.transform,
      ),
      _StepData(
        'Initializing Gemma',
        ProcessingStatus.initializingModel,
        Icons.memory,
      ),
      _StepData(
        'Processing Audio',
        ProcessingStatus.processing,
        Icons.auto_awesome,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Processing Steps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
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
                          ? Colors.green
                          : isActive
                          ? const Color(0xFF00D9FF)
                          : isFailed
                          ? Colors.red.withAlpha(50)
                          : Colors.white.withAlpha(20),
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
                            isComplete ? Icons.check : step.icon,
                            color: isComplete || isActive
                                ? Colors.white
                                : Colors.white.withAlpha(80),
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    step.label,
                    style: TextStyle(
                      color: isComplete || isActive
                          ? Colors.white
                          : Colors.white.withAlpha(80),
                      fontSize: 15,
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Error',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.errorMessage ?? 'Unknown error',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => state.clear(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(ProcessingState state) {
    final transcript = state.transcriptionResult?.text ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet, color: Colors.green, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Transcript',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${transcript.split(' ').where((w) => w.isNotEmpty).length} words',
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(50),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              transcript.isEmpty
                  ? '(Empty transcript - audio may not contain speech)'
                  : transcript,
              style: TextStyle(
                color: transcript.isEmpty
                    ? Colors.white.withAlpha(100)
                    : Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ProcessingState state) {
    final summary = state.summaryResult;
    if (summary == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00D9FF).withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D9FF).withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize, color: Color(0xFF00D9FF), size: 24),
              SizedBox(width: 12),
              Text(
                'Summary',
                style: TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary.summary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...summary.keyPoints.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00D9FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isStepComplete(ProcessingStatus current, ProcessingStatus step) {
    final order = [
      ProcessingStatus.idle,
      ProcessingStatus.convertingAudio,
      ProcessingStatus.initializingModel,
      ProcessingStatus.processing,
      ProcessingStatus.complete,
    ];
    return order.indexOf(current) > order.indexOf(step);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _StepData {
  final String label;
  final ProcessingStatus status;
  final IconData icon;
  _StepData(this.label, this.status, this.icon);
}
