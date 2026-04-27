import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/processing_state.dart';
import 'screens/home_screen.dart';
import 'screens/processing_screen.dart';
import 'ui/premium_ui.dart';
import 'utils/notification_destination.dart';

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
      create: (_) => ProcessingState(
        enableBackgroundServices: enableBackgroundServices,
        enableNotifications: enableNotifications,
      ),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Voice Note Summarizer',
        debugShowCheckedModeBanner: false,
        theme: PremiumTheme.theme(),
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
  bool _handledStartupNotification = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledStartupNotification) return;
    _handledStartupNotification = true;
    _handlePendingStartupNotification();
  }

  Future<void> _initializeApp() async {
    // Note: Initialization is handled by HomeScreen
    // This prevents double-initialization which can cause crashes
  }

  Future<void> _handlePendingStartupNotification() async {
    final state = context.read<ProcessingState>();
    await state.startupReady;
    if (!mounted) return;

    final payload = state.consumePendingSummaryNotificationPayload();
    if (payload == null) return;

    final record = await state.resolveSummaryRecord(payload);
    if (!mounted) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      state.restorePendingSummaryNotificationPayload(payload);
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => record != null
            ? notificationDestinationForRecord(record)
            : notificationFallbackDestination(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      onProcessingStart: () {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProcessingScreen()),
        );
      },
    );
  }
}
