import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../services/audio_converter.dart';
import '../services/audio_recorder_service.dart';
import '../ui/premium_ui.dart';
import 'history_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onProcessingStart;

  const HomeScreen({super.key, this.onProcessingStart});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorderService _recorderService = AudioRecorderService();
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<RecordingState>? _stateSubscription;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _setupRecorderListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  void _setupRecorderListeners() {
    _durationSubscription = _recorderService.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() => _recordingDuration = duration);
    });

    _stateSubscription = _recorderService.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isRecording =
            state == RecordingState.recording || state == RecordingState.paused;
        _isPaused = state == RecordingState.paused;
      });
    });
  }

  Future<void> _initializeApp() async {
    if (!mounted) return;
    final state = context.read<ProcessingState>();
    if (state.modelStatus != ModelStatus.ready) {
      await state.initialize();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AudioConverter.supportedExtensions
            .map((ext) => ext.substring(1))
            .toList(),
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      if (!mounted) return;
      final state = context.read<ProcessingState>();
      var addedCount = 0;
      var skippedCount = 0;

      for (final file in result.files) {
        if (file.path == null) continue;
        final queued = state.queueFile(File(file.path!));
        if (queued != null) {
          addedCount++;
        } else {
          skippedCount++;
        }
      }

      if (addedCount > 0) {
        widget.onProcessingStart?.call();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skippedCount == 0
                ? 'Added $addedCount file(s) to queue'
                : 'Added $addedCount file(s); skipped $skippedCount file(s)',
          ),
          backgroundColor: AppColors.cyan,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  Future<void> _startRecording() async {
    final success = await _recorderService.startRecording();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start recording. Please grant microphone permission.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (_isStopping) return;
    setState(() => _isStopping = true);
    try {
      final file = await _recorderService.stopRecording();
      if (file != null && mounted) {
        final state = context.read<ProcessingState>();
        state.queueFile(file);
        widget.onProcessingStart?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording added to queue'),
            backgroundColor: Color(0xFF00D9FF),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _pauseRecording() async {
    await _recorderService.pauseRecording();
  }

  Future<void> _resumeRecording() async {
    await _recorderService.resumeRecording();
  }

  Future<void> _cancelRecording() async {
    if (_isStopping) return;
    setState(() => _isStopping = true);
    try {
      await _recorderService.cancelRecording();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recording cancelled'),
          backgroundColor: Colors.grey[700],
          duration: const Duration(seconds: 1),
        ),
      );
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<ProcessingState>(
          builder: (context, state, _) {
            return PremiumBackdrop(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 40),
                    child: _buildHeader(context),
                  ),
                  const SizedBox(height: 28),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 80),
                    child: _buildHero(context),
                  ),
                  const SizedBox(height: 20),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 120),
                    child: _buildImportCard(context),
                  ),
                  const SizedBox(height: 14),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 150),
                    child: _buildRecordButton(context),
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 14),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 180),
                      child: _buildRecordingDock(context),
                    ),
                  ],
                  const SizedBox(height: 22),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 210),
                    child: _buildQuickAccessSection(context),
                  ),
                  const SizedBox(height: 22),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 240),
                    child: _buildModelStatusSection(state),
                  ),
                  const SizedBox(height: 16),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 270),
                    child: _buildProcessingSection(state),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.cyan.withAlpha(220),
                AppColors.violet.withAlpha(220),
              ],
            ),
          ),
          child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Voice Note Summarizer',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summaries that feel immediate.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: -0.5,
              ) ??
              const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          _isRecording
              ? _isPaused
                  ? 'Recording paused. Resume or stop when you are ready.'
                  : 'Recording live. The note will appear in processing once you stop.'
              : 'Import a voice note or start recording, then follow the model and processing status below.',
          style: TextStyle(
            color: Colors.white.withAlpha(165),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      onTap: _pickFile,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyan.withAlpha(18),
            ),
            child: const Icon(Icons.folder_open_rounded, color: AppColors.cyan),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Import audio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'MP3, M4A, WAV, AAC, etc.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(130),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.cyan),
        ],
      ),
    );
  }

  Widget _buildRecordButton(BuildContext context) {
    final accent = _isRecording ? AppColors.red : AppColors.cyan;
    final gradient = _isRecording
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.red, AppColors.amber.withAlpha(240)],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.cyan, AppColors.violet],
          );

    return GestureDetector(
      onTap: () {
        if (_isRecording) {
          _stopRecording();
        } else {
          _startRecording();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: accent.withAlpha(34),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  _isRecording ? 'Stop recording' : 'Start recording',
                  key: ValueKey(_isRecording),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingDock(BuildContext context) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(24),
      borderColor: AppColors.red.withAlpha(24),
      gradient: LinearGradient(
        colors: [
          AppColors.surface.withAlpha(255),
          AppColors.surfaceElevated.withAlpha(255),
        ],
      ),
      child: Row(
        children: [
          Text(
            _formatDuration(_recordingDuration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _isPaused ? 'Recording paused' : 'Recording in progress',
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: _isPaused ? _resumeRecording : _pauseRecording,
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.cyan,
            ),
          ),
          IconButton(
            onPressed: _stopRecording,
            icon: const Icon(Icons.stop_rounded, color: AppColors.red),
          ),
          IconButton(
            onPressed: _cancelRecording,
            icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('QUICK ACCESS'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAccessCard(
                icon: Icons.history_rounded,
                accent: AppColors.cyan,
                title: 'History',
                subtitle: 'View past summaries',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAccessCard(
                icon: Icons.queue_music_rounded,
                accent: AppColors.violet,
                title: 'Queue',
                subtitle: 'See what’s next',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QueueScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModelStatusSection(ProcessingState state) {
    final isReady = state.modelStatus == ModelStatus.ready;
    final isCopying = state.modelStatus == ModelStatus.copying;
    final progress = isReady ? 1.0 : state.modelDownloadProgress;
    final percentLabel = '${(progress.clamp(0.0, 1.0) * 100).round()}%';
    final footerLeft = isReady
        ? 'Gemma 4 E2B ready'
        : isCopying
            ? 'Loading Gemma model...'
            : 'Model not initialized';
    final footerRight = isReady
        ? 'Ready for notes'
        : isCopying
            ? state.modelStatusMessage
            : 'Tap download to prepare';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('MODEL STATUS'),
        const SizedBox(height: 12),
        PremiumProgressCard(
          icon: isReady ? Icons.check_rounded : Icons.memory_rounded,
          accent: isReady ? AppColors.green : AppColors.cyan,
          title: isReady ? 'Model loaded' : 'Loading model',
          subtitle: state.modelStatusMessage,
          valueLabel: percentLabel,
          progress: progress,
          footerLeft: footerLeft,
          footerRight: footerRight,
          action: state.modelStatus == ModelStatus.notDownloaded
              ? PremiumActionButton(
                  label: 'Download model',
                  icon: Icons.download_rounded,
                  onPressed: state.downloadModel,
                  expanded: true,
                  subtle: true,
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildProcessingSection(ProcessingState state) {
    final progress = state.isProcessing ? state.progress : 0.0;
    final percentLabel = '${(progress.clamp(0.0, 1.0) * 100).round()}%';
    final hasPending = state.queueCount > 0;
    final subtitle = state.currentAudioPath != null
        ? state.currentAudioPath!.split(Platform.pathSeparator).last
        : hasPending
            ? '${state.queueCount} item${state.queueCount == 1 ? '' : 's'} in queue'
            : 'Waiting for the next note';
    final footerLeft = state.statusMessage.isEmpty
        ? (hasPending ? 'Ready to process queue' : 'Idle')
        : state.statusMessage;
    final footerRight = state.currentAudioPath != null
        ? 'Current note'
        : hasPending
            ? 'Queue ready'
            : 'No active note';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('PROCESSING'),
        const SizedBox(height: 12),
        PremiumProgressCard(
          icon: state.isProcessing
              ? Icons.auto_awesome_rounded
              : Icons.queue_music_rounded,
          accent: AppColors.cyan,
          title: state.isProcessing
              ? 'Processing note'
              : hasPending
                  ? 'Queued for processing'
                  : 'Processing idle',
          subtitle: subtitle,
          valueLabel: percentLabel,
          progress: progress,
          footerLeft: footerLeft,
          footerRight: footerRight,
          action: state.isProcessing
              ? PremiumActionButton(
                  label: 'Open processing view',
                  icon: Icons.open_in_new_rounded,
                  onPressed: widget.onProcessingStart,
                  expanded: true,
                  subtle: true,
                )
              : null,
        ),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withAlpha(22), height: 1)),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(120),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withAlpha(22), height: 1)),
      ],
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withAlpha(16),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withAlpha(130),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
