import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/processing_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _systemController;
  late TextEditingController _queryController;
  late TextEditingController _transcriptionSystemController;
  late TextEditingController _transcriptionPromptController;

  @override
  void initState() {
    super.initState();
    final state = context.read<ProcessingState>();
    _systemController = TextEditingController(text: state.systemInstruction);
    _queryController = TextEditingController(text: state.queryInstruction);
    _transcriptionSystemController = TextEditingController(
      text: state.transcriptionSystem,
    );
    _transcriptionPromptController = TextEditingController(
      text: state.transcriptionPrompt,
    );
  }

  @override
  void dispose() {
    _systemController.dispose();
    _queryController.dispose();
    _transcriptionSystemController.dispose();
    _transcriptionPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to Defaults',
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Presets'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Consumer<ProcessingState>(
                    builder: (context, state, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: DropdownButton<PromptPreset>(
                          value: null,
                          hint: Text(
                            'Load a preset...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          dropdownColor: const Color(0xFF1A1A2E),
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white,
                          ),
                          items: state.presets.map((preset) {
                            return DropdownMenuItem<PromptPreset>(
                              value: preset,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    preset.name,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      context
                                          .read<ProcessingState>()
                                          .deletePreset(preset);
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (preset) {
                            if (preset != null) {
                              context.read<ProcessingState>().applyPreset(
                                preset,
                              );
                              _systemController.text = preset.systemInstruction;
                              _queryController.text = preset.queryInstruction;
                              _transcriptionSystemController.text =
                                  preset.transcriptionSystem;
                              _transcriptionPromptController.text =
                                  preset.transcriptionPrompt;
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF).withOpacity(0.1),
                    foregroundColor: const Color(0xFF00D9FF),
                  ),
                  tooltip: 'Save as Preset',
                  onPressed: () => _showSavePresetDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('System Instruction'),
            const SizedBox(height: 8),
            _buildDescription(
              'Define the persona and output format rules for the AI. '
              'Leave empty to use the default specialized summarizer persona.',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _systemController,
              hint:
                  'e.g., You are a helpful assistant who speaks like a pirate...',
              maxLines: 5,
              onChanged: (val) {
                context.read<ProcessingState>().updateSystemInstruction(val);
              },
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Query Instruction'),
            const SizedBox(height: 8),
            _buildDescription(
              'The specific task or question to ask about the transcript. '
              'The transcript will be appended after this text.',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _queryController,
              hint: 'e.g., Analyze this transcript and extract action items:',
              maxLines: 3,
              onChanged: (val) {
                context.read<ProcessingState>().updateQueryInstruction(val);
              },
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Transcription System Instruction'),
            const SizedBox(height: 8),
            _buildDescription(
              'High-level rules for the transcription process (e.g., "DO NOT TRANSLATE").',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _transcriptionSystemController,
              hint: 'e.g., DO NOT TRANSLATE. ROMANIZE ONLY...',
              maxLines: 5,
              onChanged: (val) {
                context.read<ProcessingState>().updateTranscriptionSystem(val);
              },
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Transcription Prompt'),
            const SizedBox(height: 8),
            _buildDescription('Specific instruction sent with the audio file.'),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _transcriptionPromptController,
              hint: 'e.g., Transcribe the audio exactly as spoken.',
              maxLines: 3,
              onChanged: (val) {
                context.read<ProcessingState>().updateTranscriptionPrompt(val);
              },
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF00D9FF),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildDescription(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 13,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required Function(String) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
        onChanged: onChanged,
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Reset Settings?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will revert all instructions to the default system values.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ProcessingState>().resetSettings();
              _systemController.clear();
              _queryController.clear();
              _transcriptionSystemController.clear();
              _transcriptionPromptController.clear();
              Navigator.pop(context);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: Color(0xFF00D9FF)),
            ),
          ),
        ],
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Save Preset', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Preset Name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D9FF)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<ProcessingState>().savePreset(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFF00D9FF)),
            ),
          ),
        ],
      ),
    );
  }
}
