import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/processing_state.dart';
import 'screens/home_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceNoteSummarizerApp());
}

class VoiceNoteSummarizerApp extends StatelessWidget {
  final bool enableBackgroundServices;
  final bool enableNotifications;

  const VoiceNoteSummarizerApp({
    super.key,
    this.enableBackgroundServices = true,
    this.enableNotifications = true,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          ProcessingState(
            enableBackgroundServices: enableBackgroundServices,
            enableNotifications: enableNotifications,
          ),
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
    // No auto-navigation based on state.
    // Navigation should only happen via user interaction (Notification tap or clicking item in Queue/History).
    return HomeScreen(
      onProcessingStart: () {
        // Optional: show a snackbar or small indicator instead of full screen redirect
      },
    );
  }
}
