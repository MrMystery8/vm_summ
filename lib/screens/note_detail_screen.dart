import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../services/summary_storage_service.dart';
import '../ui/premium_ui.dart';
import '../utils/slider_bounds.dart';

class NoteDetailScreen extends StatefulWidget {
  final SummaryRecord record;

  const NoteDetailScreen({super.key, required this.record});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _audioFileExists = false;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isChatLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkAudioFile();
    _setupAudioListeners();
    _messages.add(
      ChatMessage(text: 'Ask me anything about this note!', isUser: false),
    );
  }

  Future<void> _checkAudioFile() async {
    if (widget.record.sourceFilePath == null) return;
    final file = File(widget.record.sourceFilePath!);
    if (await file.exists()) {
      if (!mounted) return;
      setState(() => _audioFileExists = true);
      await _audioPlayer.setSourceDeviceFile(widget.record.sourceFilePath!);
    }
  }

  void _setupAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (!mounted) return;
      setState(() => _duration = newDuration);
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (!mounted) return;
      setState(() => _position = newPosition);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tabController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isChatLoading = true;
      _chatController.clear();
    });

    _scrollToBottom();

    try {
      final processingState = context.read<ProcessingState>();
      if (processingState.modelStatus != ModelStatus.ready) {
        await processingState.initialize();
      }

      final service = processingState.gemmaService;
      final stream = service.chatWithTranscriptStream(
        widget.record.transcript,
        text,
      );

      String accumulatedResponse = '';
      bool hasStarted = false;

      await for (final chunk in stream) {
        accumulatedResponse += chunk;
        if (!mounted) return;

        setState(() {
          if (!hasStarted) {
            _isChatLoading = false;
            _messages.add(ChatMessage(text: '', isUser: false));
            hasStarted = true;
          }

          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.removeLast();
          }
          _messages.add(ChatMessage(text: accumulatedResponse, isUser: false));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChatLoading = false;
          _messages.add(
            ChatMessage(text: 'Error: $e', isUser: false, isError: true),
          );
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.record.sourceFileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Transcript'),
            Tab(text: 'Chat'),
          ],
        ),
      ),
      body: PremiumBackdrop(
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildTranscriptTab(),
                  _buildChatTab(),
                ],
              ),
            ),
            if (_audioFileExists) _buildAudioPlayerBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayerBar() {
    return PremiumSurface(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      borderRadius: BorderRadius.circular(26),
      borderColor: AppColors.cyan.withAlpha(24),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.cyan, AppColors.violet],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withAlpha(40),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (_isPlaying) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.resume();
                      }
                    },
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
                        widget.record.sourceFileName,
                        style: TextStyle(
                          color: Colors.white.withAlpha(130),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PremiumPill(
                  icon: Icons.timelapse_rounded,
                  label: _formatDuration(_duration),
                  color: AppColors.cyan,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        AnimatedEntrance(
          delay: const Duration(milliseconds: 50),
          child: _buildOverviewHeader(),
        ),
        const SizedBox(height: 16),
        AnimatedEntrance(
          delay: const Duration(milliseconds: 110),
          child: _buildOverviewCard(
            title: 'Summary',
            child: Text(
              widget.record.summary,
              style: TextStyle(
                color: Colors.white.withAlpha(220),
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedEntrance(
          delay: const Duration(milliseconds: 160),
          child: _buildOverviewCard(
            title: 'Key points',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.record.keyPoints
                  .map(
                    (point) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 7),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [AppColors.cyan, AppColors.violet],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              point,
                              style: TextStyle(
                                color: Colors.white.withAlpha(210),
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedEntrance(
          delay: const Duration(milliseconds: 210),
          child: _buildOverviewCard(
            title: 'Action items',
            child: Text(
              widget.record.actionItems,
              style: TextStyle(
                color: Colors.white.withAlpha(210),
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewHeader() {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.cyan.withAlpha(24),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.cyan.withAlpha(18),
                  AppColors.violet.withAlpha(12),
                ],
              ),
            ),
            child: const Icon(Icons.article_outlined, color: AppColors.cyan),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.record.formattedDate,
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.record.summary.isEmpty
                      ? 'Transcript-first archive entry'
                      : widget.record.summary,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({required String title, required Widget child}) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionHeader(
            title: title,
            subtitle: title == 'Summary'
                ? 'A clean readout of the model output.'
                : title == 'Key points'
                ? 'The main ideas distilled into short bullets.'
                : 'Next steps and follow-up actions.',
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildTranscriptTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        AnimatedEntrance(
          delay: const Duration(milliseconds: 80),
          child: PremiumSurface(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PremiumSectionHeader(
                  title: 'Transcript',
                  subtitle: 'The raw note, preserved for reading and search.',
                ),
                const SizedBox(height: 14),
                Text(
                  widget.record.transcript,
                  style: TextStyle(
                    color: Colors.white.withAlpha(210),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _ChatMessageWidget(message: _messages[index]);
            },
          ),
        ),
        if (_isChatLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: CircularProgressIndicator(color: AppColors.cyan),
          ),
        PremiumSurface(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ask about this note...',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white.withAlpha(8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, AppColors.violet],
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;

  ChatMessage({required this.text, required this.isUser, this.isError = false});
}

class _ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const _ChatMessageWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? AppColors.cyan.withAlpha(18)
        : AppColors.surfaceElevated;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const CircleAvatar(
              backgroundColor: AppColors.violet,
              radius: 16,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 18),
                ),
                border: Border.all(
                  color: message.isError
                      ? AppColors.red.withAlpha(120)
                      : (isUser
                            ? AppColors.cyan.withAlpha(40)
                            : Colors.white.withAlpha(12)),
                ),
              ),
              child: isUser
                  ? Text(
                      message.text,
                      style: const TextStyle(color: Colors.white, height: 1.45),
                    )
                  : MarkdownBody(
                      data: message.text,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(color: Colors.white, height: 1.5),
                        strong: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser)
            const CircleAvatar(
              backgroundColor: AppColors.cyan,
              radius: 16,
              child: Icon(Icons.person_rounded, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
