import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/processing_state.dart';
import 'history_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

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
    _animationController.forward();
  }

  Future<void> _initializeApp() async {
    // Initialize model in background
    if (mounted) {
      final state = context.read<ProcessingState>();
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

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
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

                  // Logo
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
                    'Or share a voice note from WhatsApp',
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
                              state.queueCount > 0 || state.currentItem != null;
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
                                color: const Color(0xFF00D9FF).withAlpha(60),
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
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00D9FF), Color(0xFF6C63FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9FF).withAlpha(80),
            blurRadius: 40,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: const Color(0xFF6C63FF).withAlpha(60),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.mic_rounded, size: 56, color: Colors.white),
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
            const SizedBox(width: 12),
            const Text(
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
                    .map((item) => _buildQueueItem(item)),
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

  Widget _buildQueueItem(QueueItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(60),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.fileName,
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            item.formattedEstimate,
            style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 10),
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
