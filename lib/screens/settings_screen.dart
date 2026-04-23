import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/processing_state.dart';
import '../ui/premium_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _systemController;
  late final TextEditingController _queryController;
  late final TextEditingController _transcriptionSystemController;
  late final TextEditingController _transcriptionPromptController;

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: 'Reset to defaults',
            onPressed: () => _confirmReset(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedEntrance(
                delay: const Duration(milliseconds: 50),
                child: _buildPresetSection(context),
              ),
              const SizedBox(height: 20),
              AnimatedEntrance(
                delay: const Duration(milliseconds: 110),
                child: _buildPromptSection(
                  title: 'System instruction',
                  description:
                      'Define the persona and output rules for the summarizer.',
                  controller: _systemController,
                  maxLines: 6,
                  onChanged: (val) {
                    context.read<ProcessingState>().updateSystemInstruction(
                      val,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              AnimatedEntrance(
                delay: const Duration(milliseconds: 160),
                child: _buildPromptSection(
                  title: 'Query instruction',
                  description:
                      'The specific task prompt sent to the model after the transcript.',
                  controller: _queryController,
                  maxLines: 4,
                  onChanged: (val) {
                    context.read<ProcessingState>().updateQueryInstruction(val);
                  },
                ),
              ),
              const SizedBox(height: 16),
              AnimatedEntrance(
                delay: const Duration(milliseconds: 210),
                child: _buildPromptSection(
                  title: 'Transcription system instruction',
                  description:
                      'High-level rules for the transcription pass before summarization.',
                  controller: _transcriptionSystemController,
                  maxLines: 6,
                  onChanged: (val) {
                    context.read<ProcessingState>().updateTranscriptionSystem(
                      val,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              AnimatedEntrance(
                delay: const Duration(milliseconds: 260),
                child: _buildPromptSection(
                  title: 'Transcription prompt',
                  description: 'Specific instruction sent with the audio file.',
                  controller: _transcriptionPromptController,
                  maxLines: 4,
                  onChanged: (val) {
                    context.read<ProcessingState>().updateTranscriptionPrompt(
                      val,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetSection(BuildContext context) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumSectionHeader(
            title: 'Presets',
            subtitle: 'Load a built-in preset or save the current prompt set.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Consumer<ProcessingState>(
                  builder: (context, state, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withAlpha(10)),
                      ),
                      child: DropdownButton<PromptPreset>(
                        value: null,
                        hint: Text(
                          'Load a preset...',
                          style: TextStyle(color: Colors.white.withAlpha(120)),
                        ),
                        dropdownColor: AppColors.surfaceElevated,
                        isExpanded: true,
                        underline: const SizedBox(),
                        icon: const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: Colors.white,
                        ),
                        items: state.presets.map((preset) {
                          return DropdownMenuItem<PromptPreset>(
                            value: preset,
                            child: Row(
                              children: [
                                if (preset.isBuiltIn)
                                  const PremiumPill(
                                    icon: Icons.bolt_rounded,
                                    label: 'Built-in',
                                    color: AppColors.cyan,
                                  ),
                                if (preset.isBuiltIn) const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    preset.name,
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!preset.isBuiltIn)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: AppColors.red,
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
                          if (preset == null) return;
                          context.read<ProcessingState>().applyPreset(preset);
                          _systemController.text = preset.systemInstruction;
                          _queryController.text = preset.queryInstruction;
                          _transcriptionSystemController.text =
                              preset.transcriptionSystem;
                          _transcriptionPromptController.text =
                              preset.transcriptionPrompt;
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.save_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.cyan.withAlpha(18),
                  foregroundColor: AppColors.cyan,
                ),
                tooltip: 'Save as preset',
                onPressed: () => _showSavePresetDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromptSection({
    required String title,
    required String description,
    required TextEditingController controller,
    required int maxLines,
    required Function(String) onChanged,
  }) {
    return PremiumSurface(
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionHeader(title: title, subtitle: description),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            maxLines: maxLines,
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: true,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Reset settings?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will revert all instructions to the default system values.',
          style: TextStyle(color: Colors.white.withAlpha(180)),
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
            child: const Text('Reset', style: TextStyle(color: AppColors.cyan)),
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
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Save preset', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Preset name',
            hintStyle: TextStyle(color: Colors.white.withAlpha(120)),
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
            child: const Text('Save', style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }
}
