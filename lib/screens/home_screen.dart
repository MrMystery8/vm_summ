import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../services/audio_converter.dart';
import '../services/audio_recorder_service.dart';
import '../services/summary_storage_service.dart';
import '../ui/premium_ui.dart';
import 'history_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

enum _AccordionSection { model, queue }

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
  ProcessingState? _processingState;
  int _seenHistoryRevision = 0;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _isStopping = false;
  bool _isLoadingHistory = true;
  List<SummaryRecord> _historyRecords = [];
  _AccordionSection? _openSection;

  @override
  void initState() {
    super.initState();
    _setupRecorderListeners();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<ProcessingState>();
    if (_processingState == state) return;
    _processingState?.removeListener(_handleProcessingStateChanged);
    _processingState = state;
    _seenHistoryRevision = state.historyRevision;
    state.addListener(_handleProcessingStateChanged);
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

  Future<void> _loadHistory() async {
    try {
      final records = await SummaryStorageService().getAllRecords();
      if (!mounted) return;
      setState(() {
        _historyRecords = records;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyRecords = [];
        _isLoadingHistory = false;
      });
    }
  }

  void _handleProcessingStateChanged() {
    final revision = _processingState?.historyRevision ?? 0;
    if (revision == _seenHistoryRevision) return;
    _seenHistoryRevision = revision;
    unawaited(_loadHistory());
  }

  Future<void> _initializeApp() async {
    if (!mounted) return;
    final state = context.read<ProcessingState>();
    if (state.modelStatus != ModelStatus.ready) {
      await state.initialize();
    }
  }

  void _toggleSection(_AccordionSection section) {
    setState(() {
      _openSection = _openSection == section ? null : section;
    });
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
    _processingState?.removeListener(_handleProcessingStateChanged);
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<ProcessingState>(
          builder: (context, state, _) {
            return PremiumBackdrop(
              child: Stack(
                children: [
                  ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, 22),
                    children: [
                      SizedBox(height: compact ? 42 : 58),
                      const AnimatedEntrance(
                        delay: Duration(milliseconds: 20),
                        child: _HomeHeader(),
                      ),
                      SizedBox(height: compact ? 20 : 26),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 70),
                        child: _HeroMicSection(
                          isRecording: _isRecording,
                          isPaused: _isPaused,
                          recordingDuration: _recordingDuration,
                          onTap: () {
                            if (_isRecording) {
                              _stopRecording();
                            } else {
                              _startRecording();
                            }
                          },
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 16),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 120),
                        child: _FilePickerButton(onTap: _pickFile),
                      ),
                      if (_isRecording) ...[
                        const SizedBox(height: 14),
                        AnimatedEntrance(
                          delay: const Duration(milliseconds: 140),
                          child: _RecordingControls(
                            isPaused: _isPaused,
                            duration: _recordingDuration,
                            onPause: _pauseRecording,
                            onResume: _resumeRecording,
                            onStop: _stopRecording,
                            onCancel: _cancelRecording,
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 14 : 18),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 170),
                        child: _AccordionSectionRow(
                          title: 'Model status',
                          icon: Icons.memory_rounded,
                          accent: _modelAccent(state),
                          summary: _buildModelSummary(state),
                          isExpanded: _openSection == _AccordionSection.model,
                          onTap: () => _toggleSection(_AccordionSection.model),
                          child: ModelStatusPanel(
                            state: state,
                            onDownload: state.downloadModel,
                            onRetry: state.retryInitialize,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 210),
                        child: _AccordionSectionRow(
                          title: state.queueCount > 0
                              ? 'Queue (${state.queueCount})'
                              : 'Queue',
                          icon: Icons.queue_music_rounded,
                          accent: AppColors.cyan,
                          summary: _buildQueueSummary(state),
                          isExpanded: _openSection == _AccordionSection.queue,
                          onTap: () => _toggleSection(_AccordionSection.queue),
                          child: QueuePanel(
                            state: state,
                            onOpenQueue: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const QueueScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 250),
                        child: _AccordionSectionRow(
                          title: 'History',
                          icon: Icons.history_rounded,
                          accent: AppColors.cyan,
                          summary: _buildHistorySummary(),
                          isExpanded: false,
                          isNavigation: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HistoryScreen(),
                              ),
                            ).then((_) {
                              if (mounted) unawaited(_loadHistory());
                            });
                          },
                          child: const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 280),
                        child: _ShareHint(),
                      ),
                    ],
                  ),
                  Positioned(
                    top: compact ? 4 : 8,
                    right: 12,
                    child: AnimatedEntrance(
                      delay: const Duration(milliseconds: 40),
                      child: _HeaderSettingsButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Color _modelAccent(ProcessingState state) {
    if (state.modelStatus == ModelStatus.ready) return AppColors.green;
    if (state.modelStatus == ModelStatus.error) return AppColors.red;
    return AppColors.cyan;
  }

  Widget _buildModelSummary(ProcessingState state) {
    switch (state.modelStatus) {
      case ModelStatus.ready:
        return const _SectionBadge(
          icon: Icons.check_circle_rounded,
          label: 'Gemma 4 E2B',
          color: AppColors.green,
          maxWidth: 130,
        );
      case ModelStatus.copying:
        return _SectionBadge(
          icon: Icons.downloading_rounded,
          label: state.modelProgressLabel,
          color: AppColors.cyan,
          maxWidth: 100,
        );
      case ModelStatus.error:
        return const _SectionBadge(
          icon: Icons.warning_amber_rounded,
          label: 'Error',
          color: AppColors.red,
          maxWidth: 92,
        );
      case ModelStatus.notDownloaded:
        return const _SectionBadge(
          icon: Icons.download_rounded,
          label: 'Not ready',
          color: AppColors.cyan,
          maxWidth: 110,
        );
    }
  }

  Widget _buildQueueSummary(ProcessingState state) {
    if (state.currentItem != null) {
      return _SectionBadge(
        icon: Icons.play_circle_fill_rounded,
        label: _truncateLabel(state.currentItem!.fileName),
        color: AppColors.cyan,
        maxWidth: 152,
      );
    }

    final nextItem = state.pendingQueueItems.isNotEmpty
        ? state.pendingQueueItems.first.fileName
        : null;
    if (nextItem != null) {
      return _SectionBadge(
        icon: Icons.queue_music_rounded,
        label: _truncateLabel(nextItem),
        color: AppColors.cyan,
        maxWidth: 152,
      );
    }

    return const _SectionBadge(
      icon: Icons.check_rounded,
      label: 'Idle',
      color: AppColors.green,
      maxWidth: 84,
    );
  }

  Widget _buildHistorySummary() {
    if (_isLoadingHistory) {
      return const _SectionBadge(
        icon: Icons.sync_rounded,
        label: 'Loading',
        color: AppColors.cyan,
        maxWidth: 96,
      );
    }

    if (_historyRecords.isEmpty) {
      return const _SectionBadge(
        icon: Icons.history_toggle_off_rounded,
        label: 'Empty',
        color: AppColors.cyan,
        maxWidth: 92,
      );
    }

    final latest = _historyRecords.first;
    return _SectionBadge(
      icon: Icons.article_outlined,
      label: _truncateLabel(latest.sourceFileName),
      color: AppColors.cyan,
      maxWidth: 152,
    );
  }

  String _truncateLabel(String text) {
    if (text.length <= 18) return text;
    return '${text.substring(0, 17)}…';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              shaderCallback: (bounds) {
                return const LinearGradient(
                  colors: [
                    Color(0xFFEFFAFF),
                    Color(0xFF6DEBFF),
                    Color(0xFF6F87FF),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.48, 1.0],
                ).createShader(bounds);
              },
              child: const Text(
                'Voice Note Summarizer',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderSettingsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _HeaderSettingsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(11)),
          ),
          child: Icon(
            Icons.settings_rounded,
            color: Colors.white.withAlpha(220),
          ),
        ),
      ),
    );
  }
}

class _HeroMicSection extends StatelessWidget {
  final bool isRecording;
  final bool isPaused;
  final Duration recordingDuration;
  final VoidCallback onTap;

  const _HeroMicSection({
    required this.isRecording,
    required this.isPaused,
    required this.recordingDuration,
    required this.onTap,
  });

  String _helperText() {
    if (!isRecording) return 'Tap to record';
    if (isPaused) return 'Paused';
    return 'Recording in progress';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.48;
    final heroSize = size.clamp(164.0, 208.0).toDouble();
    final accent = isRecording ? AppColors.red : AppColors.cyan;
    final ringColor = isRecording ? AppColors.red : AppColors.violet;

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: heroSize,
            height: heroSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: heroSize,
                  height: heroSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withAlpha(26),
                        const Color(0xFF4E86FF).withAlpha(10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.44, 1.0],
                    ),
                  ),
                ),
                Container(
                  width: heroSize * 0.78,
                  height: heroSize * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isRecording
                            ? const Color(0xFFFF7A84)
                            : const Color(0xFF4DEBFF),
                        isRecording
                            ? const Color(0xFFFF8D76)
                            : const Color(0xFF36C8FF),
                        isRecording
                            ? const Color(0xFFB576FF)
                            : const Color(0xFF5598FF),
                        isRecording
                            ? const Color(0xFF7465FF)
                            : const Color(0xFF766BFF),
                      ],
                      stops: const [0.0, 0.34, 0.68, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withAlpha(30),
                        blurRadius: 22,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.34, -0.45),
                          radius: 1.12,
                          colors: [
                            isRecording
                                ? const Color(0xFFFF9AA2)
                                : const Color(0xFF84F5FF),
                            isRecording
                                ? const Color(0xFFFF8175)
                                : const Color(0xFF2F9CFF),
                            isRecording
                                ? const Color(0xFF6F61EC)
                                : const Color(0xFF5F57EA),
                          ],
                          stops: const [0.0, 0.62, 1.0],
                        ),
                      ),
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(15),
                            border: Border.all(
                              color: Colors.white.withAlpha(20),
                            ),
                          ),
                          child: SizedBox(
                            width: heroSize * 0.34,
                            height: heroSize * 0.34,
                            child: Icon(
                              isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: heroSize * 0.19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GlowRingPainter(accent: ringColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRecording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.graphic_eq_rounded,
              size: 16,
              color: accent,
            ),
            const SizedBox(width: 10),
            Text(
              _helperText(),
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (isRecording) ...[
          const SizedBox(height: 6),
          Text(
            _formatDuration(recordingDuration),
            style: TextStyle(
              color: Colors.white.withAlpha(128),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _GlowRingPainter extends CustomPainter {
  final Color accent;

  _GlowRingPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..shader = RadialGradient(
        colors: [accent.withAlpha(42), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = accent.withAlpha(28);

    canvas.drawCircle(center, size.width * 0.42, outer);
    canvas.drawCircle(center, size.width * 0.30, inner);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

class _FilePickerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _FilePickerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(1.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppColors.cyan, AppColors.violet],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.surface.withAlpha(230),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.folder_open_rounded,
                  color: AppColors.cyan,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Text(
                  'Pick Audio File',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingControls extends StatelessWidget {
  final bool isPaused;
  final Duration duration;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const _RecordingControls({
    required this.isPaused,
    required this.duration,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(22),
      borderColor: AppColors.red.withAlpha(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withAlpha(14),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: AppColors.red,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPaused ? 'Recording paused' : 'Recording',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.white.withAlpha(140),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: isPaused ? onResume : onPause,
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.cyan,
            ),
          ),
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded, color: AppColors.red),
          ),
          IconButton(
            onPressed: onCancel,
            icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _AccordionSectionRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget summary;
  final bool isExpanded;
  final bool isNavigation;
  final VoidCallback onTap;
  final Widget child;

  const _AccordionSectionRow({
    required this.title,
    required this.icon,
    required this.accent,
    required this.summary,
    required this.isExpanded,
    this.isNavigation = false,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(22),
      borderColor: isExpanded
          ? accent.withAlpha(34)
          : Colors.white.withAlpha(12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withAlpha(16),
                      ),
                      child: Icon(icon, color: accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    summary,
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isNavigation ? 0 : (isExpanded ? 0.5 : 0),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        isNavigation
                            ? Icons.chevron_right_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withAlpha(160),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isNavigation)
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: child,
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double maxWidth;

  const _SectionBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withAlpha(26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModelStatusPanel extends StatelessWidget {
  final ProcessingState state;
  final VoidCallback onDownload;
  final VoidCallback onRetry;

  const ModelStatusPanel({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = state.modelStatus == ModelStatus.ready;
    final isCopying = state.modelStatus == ModelStatus.copying;
    final hasError = state.modelStatus == ModelStatus.error;
    final progress = state.hasDeterminateModelProgress
        ? state.modelDownloadProgress.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percent = state.modelProgressLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CompactInfoLine(
          icon: hasError
              ? Icons.warning_amber_rounded
              : isReady
              ? Icons.check_circle_rounded
              : Icons.memory_rounded,
          color: hasError
              ? AppColors.red
              : isReady
              ? AppColors.green
              : AppColors.cyan,
          title: hasError
              ? 'Model error'
              : isReady
              ? 'Gemma 4 E2B ready'
              : 'Preparing the model',
          subtitle: state.modelStatusMessage,
        ),
        const SizedBox(height: 14),
        PremiumLinearProgressBar(
          progress: progress,
          accent: hasError
              ? AppColors.red
              : isReady
              ? AppColors.green
              : AppColors.cyan,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isReady
                  ? 'Ready'
                  : isCopying
                  ? 'Loading'
                  : 'Not ready',
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: 12,
              ),
            ),
            Text(
              percent,
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: 14),
          PremiumActionButton(
            label: 'Retry initialization',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
            expanded: true,
            subtle: true,
          ),
        ] else if (!isReady) ...[
          if (!isCopying) ...[
            const SizedBox(height: 14),
            PremiumActionButton(
              label: 'Download model',
              icon: Icons.download_rounded,
              onPressed: onDownload,
              expanded: true,
              subtle: true,
            ),
          ],
        ],
      ],
    );
  }
}

class QueuePanel extends StatelessWidget {
  final ProcessingState state;
  final VoidCallback onOpenQueue;

  const QueuePanel({super.key, required this.state, required this.onOpenQueue});

  @override
  Widget build(BuildContext context) {
    final items = state.displayQueueItems;

    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CompactInfoLine(
            icon: Icons.queue_music_rounded,
            color: AppColors.cyan,
            title: 'Queue is empty',
            subtitle: 'Record a note or pick a file to add the next item.',
          ),
          const SizedBox(height: 14),
          PremiumActionButton(
            label: 'Open queue',
            icon: Icons.open_in_new_rounded,
            onPressed: onOpenQueue,
            expanded: true,
            subtle: true,
          ),
        ],
      );
    }

    final current = state.currentItem;
    final progress = state.queueProgress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current != null) ...[
          _CompactInfoLine(
            icon: Icons.play_circle_fill_rounded,
            color: AppColors.cyan,
            title: current.fileName,
            subtitle: state.statusMessage.isEmpty
                ? 'Processing now'
                : state.statusMessage,
          ),
          const SizedBox(height: 12),
          PremiumLinearProgressBar(progress: progress, accent: AppColors.cyan),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.queuePositionLabel,
                style: TextStyle(
                  color: Colors.white.withAlpha(140),
                  fontSize: 12,
                ),
              ),
              Text(
                state.queueProgressLabel,
                style: TextStyle(
                  color: Colors.white.withAlpha(140),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ] else ...[
          _CompactInfoLine(
            icon: Icons.queue_music_rounded,
            color: AppColors.cyan,
            title:
                '${items.length} item${items.length == 1 ? '' : 's'} in queue',
            subtitle: _truncateLabel(items.first.fileName),
          ),
        ],
        const SizedBox(height: 14),
        ...items
            .take(3)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MiniQueueItem(item: item),
              ),
            ),
        if (items.length > 3) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+${items.length - 3} more item${items.length - 3 == 1 ? '' : 's'}',
              style: TextStyle(
                color: Colors.white.withAlpha(120),
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        PremiumActionButton(
          label: 'Open queue',
          icon: Icons.open_in_new_rounded,
          onPressed: onOpenQueue,
          expanded: true,
          subtle: true,
        ),
      ],
    );
  }

  String _truncateLabel(String text) {
    if (text.length <= 36) return text;
    return '${text.substring(0, 35)}…';
  }
}

class _CompactInfoLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _CompactInfoLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(16),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withAlpha(135),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniQueueItem extends StatelessWidget {
  final QueueItem item;

  const _MiniQueueItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.status == QueueItemStatus.processing
                  ? AppColors.cyan
                  : item.status == QueueItemStatus.failed
                  ? AppColors.red
                  : Colors.white.withAlpha(70),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(220),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.status == QueueItemStatus.processing
                ? 'Now'
                : item.status == QueueItemStatus.failed
                ? 'Failed'
                : item.formattedEstimate,
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ShareHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: Colors.white.withAlpha(92),
          ),
          const SizedBox(width: 8),
          Text(
            'Or share audio from WhatsApp',
            style: TextStyle(
              color: Colors.white.withAlpha(105),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
