import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitdesktop/core/git/git_isolate_manager.dart';
import 'package:gitdesktop/core/git/dynamic_library_service.dart';
import 'theme.dart';
import 'nav.dart';

/// Main entry point for the application
///
/// This sets up:
/// - Riverpod state management
/// - GitIsolateManager (background isolate for FFI calls)
/// - go_router navigation
/// - Material 3 theming with light/dark modes
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

    // Quick visibility into native library availability on startup
    DynamicLibraryService.logAvailability(probeSymbols: false);

  // Initialize Git isolate manager (required before any Git operations)
  final gitManager = GitIsolateManager();
  // Skip isolate initialization on web to avoid unsupported errors
  try {
    await gitManager.initialize();
  } catch (e) {
    // Safety net; initialization method already avoids rethrow, but keep this just in case
    debugPrint('[main] Git isolate init skipped/failed: $e');
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GitDesktop',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
