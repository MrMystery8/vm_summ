import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/processing_state.dart';
import 'screens/home_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/results_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceNoteSummarizerApp());
}

class VoiceNoteSummarizerApp extends StatelessWidget {
  const VoiceNoteSummarizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProcessingState(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Voice Note Summarizer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00D9FF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        ),
        home: const MainNavigator(),
      ),
    );
  }
}

/// Main navigator handling screen transitions based on processing state
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Note: Initialization is handled by HomeScreen
    // This prevents double-initialization which can cause crashes
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcessingState>(
      builder: (context, state, _) {
        // Auto-navigate based on processing state
        if (state.isProcessing) {
          return const ProcessingScreen();
        }

        if (state.status == ProcessingStatus.complete) {
          return const ResultsScreen();
        }

        // Default: show home screen
        return HomeScreen(
          onProcessingStart: () {
            // Navigation is automatic via state changes
          },
        );
      },
    );
  }
}
