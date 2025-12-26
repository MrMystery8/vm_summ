import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/processing_state.dart';
import '../services/audio_recorder_service.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'history_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';
import '../services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Home screen with modern gradient design
class HomeScreen extends StatefulWidget {
  final VoidCallback? onProcessingStart;

  const HomeScreen({super.key, this.onProcessingStart});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Recording state
  final AudioRecorderService _recorderService = AudioRecorderService();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<RecordingState>? _stateSubscription;
  bool _isPaused = false;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _initializeApp();
    _setupRecorderListeners();
    _animationController.forward();
  }

  void _setupRecorderListeners() {
    _durationSubscription = _recorderService.durationStream.listen((duration) {
      setState(() {
        _recordingDuration = duration;
      });
    });

    _stateSubscription = _recorderService.stateStream.listen((state) {
      setState(() {
        _isRecording =
            state == RecordingState.recording || state == RecordingState.paused;
        _isPaused = state == RecordingState.paused;
      });
    });
  }

  Future<void> _initializeApp() async {
    // Initialize model in background
    if (mounted) {
      final state = context.read<ProcessingState>();

      // Initialize Notification Service
      await NotificationService().initialize(
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification tap - Navigate to History
          if (response.payload != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            );
          }
        },
      );

      if (state.modelStatus != ModelStatus.ready) {
        await state.initialize();
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true, // Allow multiple files
      );

      if (result != null && result.files.isNotEmpty) {
        if (!mounted) return;
        final state = context.read<ProcessingState>();
        for (final file in result.files) {
          if (file.path != null) {
            state.queueFile(File(file.path!));
          }
        }
        widget.onProcessingStart?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${result.files.length} file(s) to queue'),
              backgroundColor: const Color(0xFF00D9FF),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recording cancelled'),
            backgroundColor: Colors.grey[700],
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                            ),
                            tooltip: 'Settings',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SettingsScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Logo - now tappable for recording
                      _buildLogo(),

                      const SizedBox(height: 24),

                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF00D9FF), Color(0xFF6C63FF)],
                        ).createShader(bounds),
                        child: const Text(
                          'Voice Note Summarizer',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Powered by Gemma 3n AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Model status card
                      _buildModelStatusCard(),

                      const SizedBox(height: 16),

                      // Queue status card (shows when processing)
                      const _QueueStatusCard(),

                      const SizedBox(height: 16),

                      // Main action button
                      _buildMainButton(),

                      const SizedBox(height: 16),

                      // Secondary text
                      Text(
                        'Tap the mic to record, or share from WhatsApp',
                        style: TextStyle(
                          color: Colors.white.withAlpha(80),
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Queue and History buttons row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Queue button
                          Consumer<ProcessingState>(
                            builder: (context, state, _) {
                              final hasItems =
                                  state.queueCount > 0 ||
                                  state.currentItem != null;
                              return OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const QueueScreen(),
                                    ),
                                  );
                                },
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(Icons.queue_music, size: 18),
                                    if (hasItems)
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
                                            '${state.queueCount + (state.currentItem != null ? 1 : 0)}',
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
                                label: const Text('Queue'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF00D9FF),
                                  side: BorderSide(
                                    color: const Color(
                                      0xFF00D9FF,
                                    ).withAlpha(60),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 12),

                          // History button
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HistoryScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('History'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00D9FF),
                              side: BorderSide(
                                color: const Color(0xFF00D9FF).withAlpha(60),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),

            // Recording overlay
            if (_isRecording) _buildRecordingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return GestureDetector(
      onTap: _isRecording ? null : _startRecording,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: _isRecording ? 140 : 120,
        height: _isRecording ? 140 : 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isRecording
                ? [const Color(0xFFFF4444), const Color(0xFFFF6B6B)]
                : [const Color(0xFF00D9FF), const Color(0xFF6C63FF)],
          ),
          boxShadow: [
            BoxShadow(
              color: _isRecording
                  ? const Color(0xFFFF4444).withAlpha(80)
                  : const Color(0xFF00D9FF).withAlpha(80),
              blurRadius: _isRecording ? 60 : 40,
              spreadRadius: _isRecording ? 10 : 5,
            ),
            BoxShadow(
              color: _isRecording
                  ? const Color(0xFFFF6B6B).withAlpha(60)
                  : const Color(0xFF6C63FF).withAlpha(60),
              blurRadius: 60,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Icon(
          _isRecording ? Icons.mic : Icons.mic_rounded,
          size: _isRecording ? 64 : 56,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Blur effect
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Block touches
              child: Container(
                color: Colors.black.withAlpha(150),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isPaused
                        ? Colors.orange.withAlpha(30)
                        : const Color(0xFFFF4444).withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isPaused
                          ? Colors.orange.withAlpha(100)
                          : const Color(0xFFFF4444).withAlpha(100),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isPaused)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.0, end: 0.5),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOut,
                            builder: (context, opacity, child) {
                              return Opacity(
                                opacity: opacity,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              );
                            },
                            onEnd: () {
                              if (_isRecording && !_isPaused) setState(() {});
                            },
                          ),
                        ),
                      Text(
                        _isPaused ? 'Thinking (Paused)...' : 'Listening...',
                        style: TextStyle(
                          color: _isPaused
                              ? Colors.orange
                              : const Color(0xFFFF4444),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Timer
                Text(
                  _formatDuration(_recordingDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'monospace',
                    letterSpacing: -2,
                  ),
                ),

                const SizedBox(height: 48),

                // Real Waveform using audio_waveforms package
                if (_isRecording)
                  SizedBox(
                    height: 80, // Keeps layout compact
                    child: Center(
                      child: OverflowBox(
                        minHeight: 0,
                        maxHeight: 500,
                        alignment: Alignment.center,
                        child: Transform.scale(
                          scaleY: 6.0, // 6x Boost (High Sensitivity)
                          child: AudioWaveforms(
                            size: Size(
                              MediaQuery.of(context).size.width * 0.9,
                              60,
                            ), // 60px Base Height to prevent internal flat-topping
                            recorderController:
                                _recorderService.recorderController,
                            enableGesture: false,
                            waveStyle: WaveStyle(
                              waveColor: const Color(0xFF00D9FF),
                              extendWaveform: true,
                              showMiddleLine: false,
                              spacing: 5.0,
                              waveThickness:
                                  2.0, // Thin lines to keep silence subtle
                              showDurationLabel: false,
                              gradient: ui.Gradient.linear(
                                const Offset(0, 0),
                                const Offset(
                                  0,
                                  60,
                                ), // Gradient matches 60px height
                                [
                                  const Color(0xFF00D9FF),
                                  const Color(0xFFFF4444),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 60,
                    width: MediaQuery.of(context).size.width * 0.8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        30,
                        (index) => Container(
                          width: 4,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D9FF).withAlpha(100),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),

                const Spacer(flex: 3),

                // Controls
                Padding(
                  padding: const EdgeInsets.only(bottom: 64),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Cancel Button
                      _buildControlBtn(
                        icon: Icons.close,
                        label: 'Cancel',
                        onTap: _cancelRecording,
                        color: Colors.white.withAlpha(80),
                        size: 56,
                      ),

                      // Pause/Resume Button
                      _buildControlBtn(
                        icon: _isPaused ? Icons.mic : Icons.pause,
                        label: _isPaused ? 'Resume' : 'Pause',
                        onTap: _isPaused ? _resumeRecording : _pauseRecording,
                        color: Colors.white,
                        bgColor: Colors.white.withAlpha(20),
                        size: 72,
                        iconSize: 32,
                      ),

                      // Stop Button
                      GestureDetector(
                        onTap: _stopRecording,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00D9FF),
                                    Color(0xFF6C63FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF6C63FF,
                                    ).withAlpha(100),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: _isStopping
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Done',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Color? bgColor,
    double size = 56,
    double iconSize = 24,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor ?? Colors.white.withAlpha(20),
              border: Border.all(color: Colors.white.withAlpha(30), width: 1),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: iconSize),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(150),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelStatusCard() {
    return Consumer<ProcessingState>(
      builder: (context, state, _) {
        final isReady = state.modelStatus == ModelStatus.ready;
        final isCopying = state.modelStatus == ModelStatus.copying;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isReady
                  ? Colors.green.withAlpha(50)
                  : const Color(0xFF00D9FF).withAlpha(30),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isReady
                      ? Colors.green.withAlpha(30)
                      : const Color(0xFF00D9FF).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isReady ? Icons.check_circle : Icons.memory,
                  color: isReady ? Colors.green : const Color(0xFF00D9FF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gemma 3n E2B',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.modelStatusMessage,
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 12,
                      ),
                    ),
                    if (isCopying) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: state.modelDownloadProgress,
                        backgroundColor: Colors.white.withAlpha(30),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00D9FF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF00D9FF), Color(0xFF6C63FF)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D9FF).withAlpha(60),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Text(
              'Pick Audio File',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Queue status card showing current processing and queued items
class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcessingState>(
      builder: (context, state, _) {
        final hasQueue =
            state.queueItems.isNotEmpty || state.currentItem != null;
        if (!hasQueue && state.status == ProcessingStatus.idle) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00D9FF).withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    state.status == ProcessingStatus.processing
                        ? Icons.sync
                        : Icons.queue_music,
                    color: const Color(0xFF00D9FF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.status == ProcessingStatus.processing
                        ? 'Processing...'
                        : state.queueItems.isNotEmpty
                        ? 'Queue (${state.queueItems.length})'
                        : 'Ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (state.queueItems.isNotEmpty)
                    Text(
                      'Est: ${_formatDuration(state.totalQueueEstimate)}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),

              // Current item
              if (state.currentItem != null) ...[
                const SizedBox(height: 12),
                _buildCurrentItem(state),
              ],

              // Progress bar
              if (state.status == ProcessingStatus.processing ||
                  state.status == ProcessingStatus.convertingAudio) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: state.progress,
                  backgroundColor: Colors.white.withAlpha(20),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00D9FF)),
                ),
                const SizedBox(height: 4),
                Text(
                  state.statusMessage,
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 11,
                  ),
                ),
              ],

              // Queue list
              if (state.queueItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2A2A3E), height: 1),
                const SizedBox(height: 8),
                ...state.queueItems
                    .take(3)
                    .map((item) => _buildQueueItem(context, item)),
                if (state.queueItems.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${state.queueItems.length - 3} more',
                      style: TextStyle(
                        color: Colors.white.withAlpha(80),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentItem(ProcessingState state) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF00D9FF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            state.currentItem!.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          state.currentItem!.formattedEstimate,
          style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildQueueItem(BuildContext context, QueueItem item) {
    final isFailed = item.status == QueueItemStatus.failed;
    return GestureDetector(
      onTap: () {
        if (isFailed && item.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${item.errorMessage}'),
              backgroundColor: const Color(0xFFFF4444),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isFailed
                    ? const Color(0xFFFF4444)
                    : Colors.white.withAlpha(60),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.fileName,
                style: TextStyle(
                  color: isFailed
                      ? const Color(0xFFFF4444)
                      : Colors.white.withAlpha(140),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              isFailed ? 'Failed (Tap)' : item.formattedEstimate,
              style: TextStyle(
                color: isFailed
                    ? const Color(0xFFFF4444)
                    : Colors.white.withAlpha(80),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}
