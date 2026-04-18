import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import '../services/summary_storage_service.dart';
import '../utils/slider_bounds.dart';

/// Results screen showing summary, transcript, and audio playback
/// Adapted from ResultsScreen to work with SummaryRecord (for history/notifications)
class SummaryResultScreen extends StatefulWidget {
  final SummaryRecord record;

  const SummaryResultScreen({super.key, required this.record});

  @override
  State<SummaryResultScreen> createState() => _SummaryResultScreenState();
}

class _SummaryResultScreenState extends State<SummaryResultScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _transcriptExpanded = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Set initial duration if available
    if (widget.record.audioDurationSeconds > 0) {
      _duration = Duration(seconds: widget.record.audioDurationSeconds);
    }
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

  Future<void> _togglePlay() async {
    final audioPath = widget.record.sourceFilePath;
    if (audioPath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(audioPath));
      setState(() => _isPlaying = true);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF00D9FF),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareResults() {
    String shareText = '📝 Voice Note Summary\n\n';

    shareText += '💡 Summary:\n${widget.record.summary}\n\n';

    if (widget.record.keyPoints.isNotEmpty) {
      shareText += '🔹 Key Points:\n';
      for (final bullet in widget.record.keyPoints) {
        shareText += '• $bullet\n';
      }
      shareText += '\n';
    }

    if (widget.record.actionItems.isNotEmpty &&
        widget.record.actionItems.toLowerCase() != 'none' &&
        widget.record.actionItems.toLowerCase() != 'n/a') {
      shareText += '✅ Action Items:\n${widget.record.actionItems}\n\n';
    }

    if (widget.record.transcript.isNotEmpty) {
      shareText += '📄 Full Transcript:\n${widget.record.transcript}';
    }

    Share.share(shareText);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final hasActionItems =
        record.actionItems.isNotEmpty &&
        record.actionItems.toLowerCase() != 'none' &&
        record.actionItems.toLowerCase() != 'n/a';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: const Color(0xFF0D0D1A),
            pinned: true,
            expandedHeight: 120,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded, color: Color(0xFF00D9FF)),
                onPressed: _shareResults,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF00D9FF).withAlpha(30),
                      const Color(0xFF0D0D1A),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Audio player card (only if path exists)
                if (record.sourceFilePath != null)
                  _buildAudioPlayerCard(
                    record.sourceFilePath!,
                    record.sourceFileName,
                  ),

                const SizedBox(height: 24),

                // Summary card
                _buildSummaryCard(record.summary),

                const SizedBox(height: 20),

                // Key points card
                if (record.keyPoints.isNotEmpty)
                  _buildKeyPointsCard(record.keyPoints),

                const SizedBox(height: 20),

                // Action items card
                if (hasActionItems) _buildActionItemsCard(record.actionItems),

                const SizedBox(height: 20),

                // Transcript card
                if (record.transcript.isNotEmpty)
                  _buildTranscriptCard(record.transcript),

                const SizedBox(height: 24),

                // Metadata row
                _buildMetadataRow(record),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerCard(String audioPath, String fileName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00D9FF).withAlpha(25),
            const Color(0xFF6C63FF).withAlpha(15),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00D9FF).withAlpha(40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9FF).withAlpha(20),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Play/pause button
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 64,
                  height: 64,
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
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                    const SizedBox(height: 4),
                    Text(
                      fileName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Duration
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    color: Color(0xFF00D9FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: const Color(0xFF00D9FF),
              inactiveTrackColor: Colors.white.withAlpha(30),
              thumbColor: Colors.white,
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
          // Time labels
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

  Widget _buildSummaryCard(String summary) {
    return _buildCard(
      icon: Icons.lightbulb_rounded,
      iconColor: const Color(0xFFFFD700),
      title: 'Summary',
      onCopy: () => _copyToClipboard(summary, 'Summary'),
      child: Text(
        summary,
        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
      ),
    );
  }

  Widget _buildKeyPointsCard(List<String> bullets) {
    return _buildCard(
      icon: Icons.format_list_bulleted_rounded,
      iconColor: const Color(0xFF00D9FF),
      title: 'Key Points',
      onCopy: () => _copyToClipboard(bullets.join('\n• '), 'Key points'),
      child: Column(
        children: bullets
            .map(
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
                          colors: [Color(0xFF00D9FF), Color(0xFF6C63FF)],
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
            )
            .toList(),
      ),
    );
  }

  Widget _buildActionItemsCard(String actionItems) {
    return _buildCard(
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF4CAF50),
      title: 'Action Items',
      onCopy: () => _copyToClipboard(actionItems, 'Action items'),
      child: Text(
        actionItems,
        style: TextStyle(
          color: Colors.white.withAlpha(220),
          fontSize: 15,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildTranscriptCard(String transcript) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() => _transcriptExpanded = !_transcriptExpanded);
              if (_transcriptExpanded) {
                _animationController.forward();
              } else {
                _animationController.reverse();
              }
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
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
                          'Full Transcript',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${transcript.split(' ').where((w) => w.isNotEmpty).length} words',
                          style: TextStyle(
                            color: Colors.white.withAlpha(100),
                            fontSize: 13,
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
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  transcript.isEmpty ? '(No transcript available)' : transcript,
                  style: TextStyle(
                    color: transcript.isEmpty
                        ? Colors.white.withAlpha(100)
                        : Colors.white.withAlpha(200),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            crossFadeState: _transcriptExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onCopy,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                color: Colors.white.withAlpha(120),
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildMetadataRow(SummaryRecord record) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_duration.inSeconds > 0) ...[
          _buildMetadataChip(Icons.timer_rounded, _formatDuration(_duration)),
          const SizedBox(width: 12),
        ],
        _buildMetadataChip(
          Icons.text_fields_rounded,
          '${record.transcript.split(' ').where((w) => w.isNotEmpty).length} words',
        ),
      ],
    );
  }

  Widget _buildMetadataChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withAlpha(120)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
