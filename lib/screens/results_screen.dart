import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/processing_state.dart';
import '../ui/premium_ui.dart';

class ResultsScreen extends StatefulWidget {
  final String? debugAudioPath;
  final bool enableAudioPlayer;

  const ResultsScreen({
    super.key,
    this.debugAudioPath,
    this.enableAudioPlayer = true,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _transcriptExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableAudioPlayer) {
      _audioPlayer = AudioPlayer();
      _setupAudioPlayer();
    }
  }

  void _setupAudioPlayer() {
    final audioPlayer = _audioPlayer;
    if (audioPlayer == null) return;

    audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });

    audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _togglePlay(String? audioPath) async {
    if (audioPath == null) return;
    final audioPlayer = _audioPlayer;
    if (audioPlayer == null) return;

    if (_isPlaying) {
      await audioPlayer.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      final atEnd =
          _duration.inMilliseconds > 0 &&
          _position.inMilliseconds >= _playableEndPosition().inMilliseconds;
      await audioPlayer.play(
        DeviceFileSource(audioPath),
        position: atEnd ? Duration.zero : _position,
      );
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.cyan,
      ),
    );
  }

  void _shareResults(ProcessingState state) {
    final summary = state.summaryResult;
    final transcript = state.transcriptionResult;

    String shareText = 'Voice Note Summary\n\n';

    if (summary != null) {
      shareText += 'Summary:\n${summary.summary}\n\n';
      if (summary.keyPoints.isNotEmpty) {
        shareText += 'Key points:\n';
        for (final point in summary.keyPoints) {
          shareText += '- $point\n';
        }
        shareText += '\n';
      }
      if (summary.hasActionItems) {
        shareText += 'Action items:\n${summary.actionItems}\n\n';
      }
    }

    if (transcript != null && transcript.text.isNotEmpty) {
      shareText += 'Transcript:\n${transcript.text}';
    }

    Share.share(shareText);
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.debugAudioPath != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: PremiumBackdrop(
          child: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              SafeArea(
                top: false,
                child: _buildAudioPlayerDock(widget.debugAudioPath!),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<ProcessingState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: PremiumBackdrop(
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        pinned: true,
                        elevation: 0,
                        expandedHeight: 140,
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed: () => state.clear(),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(
                              Icons.share_rounded,
                              color: AppColors.cyan,
                            ),
                            onPressed: () => _shareResults(state),
                          ),
                        ],
                        flexibleSpace: FlexibleSpaceBar(
                          titlePadding: const EdgeInsetsDirectional.only(
                            start: 16,
                            bottom: 16,
                          ),
                          title: const Text(
                            'Summary',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          background: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.cyan.withAlpha(18),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            if (state.summaryResult != null)
                              AnimatedEntrance(
                                delay: const Duration(milliseconds: 120),
                                child: _buildSummaryCard(state.summaryResult!),
                              ),
                            if (state.summaryResult != null)
                              const SizedBox(height: 16),
                            if (state.summaryResult != null &&
                                state.summaryResult!.keyPoints.isNotEmpty)
                              AnimatedEntrance(
                                delay: const Duration(milliseconds: 180),
                                child: _buildKeyPointsCard(
                                  state.summaryResult!.keyPoints,
                                ),
                              ),
                            if (state.summaryResult != null &&
                                state.summaryResult!.keyPoints.isNotEmpty)
                              const SizedBox(height: 16),
                            if (state.summaryResult != null &&
                                state.summaryResult!.hasActionItems)
                              AnimatedEntrance(
                                delay: const Duration(milliseconds: 220),
                                child: _buildActionItemsCard(
                                  state.summaryResult!.actionItems,
                                ),
                              ),
                            if (state.summaryResult != null &&
                                state.summaryResult!.hasActionItems)
                              const SizedBox(height: 16),
                            if (state.transcriptionResult != null)
                              AnimatedEntrance(
                                delay: const Duration(milliseconds: 260),
                                child: _buildTranscriptCard(
                                  state.transcriptionResult!.text,
                                ),
                              ),
                            const SizedBox(height: 16),
                            AnimatedEntrance(
                              delay: const Duration(milliseconds: 300),
                              child: _buildMetadataRow(state),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.currentAudioPath != null)
                  SafeArea(
                    top: false,
                    child: _buildAudioPlayerDock(state.currentAudioPath!),
                  ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.read<ProcessingState>().clear(),
            backgroundColor: AppColors.cyan,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text(
              'New Summary',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioPlayerDock(String audioPath) {
    return CompactPlaybackStrip(
      isPlaying: _isPlaying,
      position: _position,
      duration: _duration,
      onTogglePlay: () => _togglePlay(audioPath),
      onSeek: (value) {
        _seekPlayback(value);
      },
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    );
  }

  Future<void> _seekPlayback(Duration value) async {
    final audioPlayer = _audioPlayer;
    if (audioPlayer == null) return;

    final safePosition = _clampPlayablePosition(value);
    if (mounted) {
      setState(() {
        _position = safePosition;
        if (_isPlaying &&
            _duration > Duration.zero &&
            safePosition >= _playableEndPosition()) {
          _isPlaying = false;
        }
      });
    }

    await audioPlayer.seek(safePosition);

    if (_duration > Duration.zero && safePosition >= _playableEndPosition()) {
      await audioPlayer.pause();
    }
  }

  Duration _clampPlayablePosition(Duration value) {
    if (_duration <= Duration.zero) return value;
    if (value <= Duration.zero) return Duration.zero;
    final playableEnd = _playableEndPosition();
    return value > playableEnd ? playableEnd : value;
  }

  Duration _playableEndPosition() {
    if (_duration <= Duration.zero) return Duration.zero;
    final guard = _duration.inMilliseconds < 1000
        ? _duration.inMilliseconds ~/ 2
        : 500;
    return Duration(
      milliseconds: (_duration.inMilliseconds - guard).clamp(
        0,
        _duration.inMilliseconds,
      ),
    );
  }

  Widget _buildSummaryCard(SummaryResult summary) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
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
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyPointsCard(List<String> bullets) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumSectionHeader(
            title: 'Key points',
            subtitle: 'The main ideas, tightened into short bullets.',
          ),
          const SizedBox(height: 14),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
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
                      bullet,
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItemsCard(String actionItems) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      borderColor: AppColors.green.withAlpha(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumSectionHeader(
            title: 'Action items',
            subtitle: 'Anything that needs a follow-up or next step.',
          ),
          const SizedBox(height: 14),
          Text(
            actionItems,
            style: TextStyle(
              color: Colors.white.withAlpha(220),
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard(String transcript) {
    final wordCount = transcript.split(' ').where((w) => w.isNotEmpty).length;

    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() => _transcriptExpanded = !_transcriptExpanded);
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(10),
                    ),
                    child: Icon(
                      Icons.description_rounded,
                      color: Colors.white.withAlpha(180),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Full transcript',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '$wordCount words',
                          style: TextStyle(
                            color: Colors.white.withAlpha(110),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: Colors.white.withAlpha(120),
                    onPressed: () => _copyToClipboard(transcript, 'Transcript'),
                  ),
                  AnimatedRotation(
                    turns: _transcriptExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                transcript,
                style: TextStyle(
                  color: Colors.white.withAlpha(210),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            crossFadeState: _transcriptExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(ProcessingState state) {
    final summary = state.summaryResult;
    final transcript = state.transcriptionResult;

    return Row(
      children: [
        Expanded(
          child: PremiumSurface(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transcript',
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${transcript?.text.split(' ').where((w) => w.isNotEmpty).length ?? 0} words',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PremiumSurface(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary',
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  summary?.keyPoints.length.toString() ?? '0',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
