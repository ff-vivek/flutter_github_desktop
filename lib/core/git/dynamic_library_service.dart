import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service for loading platform-specific libgit2 binaries
///
/// Handles conditional loading of the correct shared library:
/// - Windows: libgit2.dll
/// - macOS: libgit2.dylib
/// - Linux: libgit2.so
///
/// Libraries should be bundled in platform-specific directories:
/// - windows/libgit2.dll
/// - macos/libgit2.dylib
/// - linux/libgit2.so
///
/// If bundled library is not found, falls back to system library.
class DynamicLibraryService {
  static DynamicLibrary? _library;

  /// Get the loaded libgit2 library instance
  ///
  /// Throws if library cannot be loaded.
  static DynamicLibrary get library {
    if (_library == null) {
      throw StateError('libgit2 not loaded. Call initialize() first.');
    }
    return _library!;
  }

  /// Check if library is already loaded
  static bool get isLoaded => _library != null;

  /// Initialize and load the platform-specific libgit2 library
  ///
  /// Safe to call multiple times (idempotent).
  static Future<void> initialize() async {
    if (_library != null) {
      debugPrint('[DynamicLibraryService] Already initialized');
      return;
    }

    try {
      debugPrint('[DynamicLibraryService] Loading libgit2...');

      if (Platform.isWindows) {
        _library = _loadWindows();
      } else if (Platform.isMacOS) {
        _library = _loadMacOS();
      } else if (Platform.isLinux) {
        _library = _loadLinux();
      } else {
        throw UnsupportedError('Platform ${Platform.operatingSystem} not supported');
      }

      debugPrint('[DynamicLibraryService] Successfully loaded libgit2');
    } catch (e) {
      debugPrint('[DynamicLibraryService] Failed to load libgit2: $e');
      rethrow;
    }
  }

  /// Load libgit2.dll on Windows
  static DynamicLibrary _loadWindows() {
    const libraryName = 'libgit2.dll';
    
    // Try bundled library first
    final bundledPath = 'windows/$libraryName';
    try {
      debugPrint('[DynamicLibraryService] Attempting to load bundled: $bundledPath');
      return DynamicLibrary.open(bundledPath);
    } catch (e) {
      debugPrint('[DynamicLibraryService] Bundled library not found: $e');
    }

    // Fall back to system library
    try {
      debugPrint('[DynamicLibraryService] Attempting to load system: $libraryName');
      return DynamicLibrary.open(libraryName);
    } catch (e) {
      throw LibraryLoadException(
        'Failed to load $libraryName. '
        'Ensure libgit2 is installed or bundle it in windows/ directory.',
      );
    }
  }

  /// Load libgit2.dylib on macOS
  static DynamicLibrary _loadMacOS() {
    const libraryName = 'libgit2.dylib';
    
    // Try bundled library first
    final bundledPath = 'macos/$libraryName';
    try {
      debugPrint('[DynamicLibraryService] Attempting to load bundled: $bundledPath');
      return DynamicLibrary.open(bundledPath);
    } catch (e) {
      debugPrint('[DynamicLibraryService] Bundled library not found: $e');
    }

    // Try common Homebrew installation path
    final homebrewPath = '/opt/homebrew/lib/$libraryName';
    try {
      debugPrint('[DynamicLibraryService] Attempting Homebrew path: $homebrewPath');
      return DynamicLibrary.open(homebrewPath);
    } catch (e) {
      debugPrint('[DynamicLibraryService] Homebrew library not found: $e');
    }

    // Fall back to system library
    try {
      debugPrint('[DynamicLibraryService] Attempting to load system: $libraryName');
      return DynamicLibrary.open(libraryName);
    } catch (e) {
      throw LibraryLoadException(
        'Failed to load $libraryName. '
        'Install via Homebrew (brew install libgit2) or bundle it in macos/ directory.',
      );
    }
  }

  /// Load libgit2.so on Linux
  static DynamicLibrary _loadLinux() {
    const libraryName = 'libgit2.so';
    
    // Try bundled library first
    final bundledPath = 'linux/$libraryName';
    try {
      debugPrint('[DynamicLibraryService] Attempting to load bundled: $bundledPath');
      return DynamicLibrary.open(bundledPath);
    } catch (e) {
      debugPrint('[DynamicLibraryService] Bundled library not found: $e');
    }

    // Try versioned system library (common on Linux)
    for (final version in ['1.7', '1.6', '1.5', '1.4', '1.3', '1.2', '1.1', '1.0']) {
      try {
        final versionedName = 'libgit2.so.$version';
        debugPrint('[DynamicLibraryService] Attempting: $versionedName');
        return DynamicLibrary.open(versionedName);
      } catch (e) {
        // Continue to next version
      }
    }

    // Fall back to unversioned system library
    try {
      debugPrint('[DynamicLibraryService] Attempting to load system: $libraryName');
      return DynamicLibrary.open(libraryName);
    } catch (e) {
      throw LibraryLoadException(
        'Failed to load $libraryName. '
        'Install via package manager (apt install libgit2-dev) or bundle it in linux/ directory.',
      );
    }
  }

  /// Dispose and unload the library
  ///
  /// Note: DynamicLibrary doesn't provide an unload mechanism,
  /// so this just clears the reference. The OS will unload when the process exits.
  static void dispose() {
    _library = null;
    debugPrint('[DynamicLibraryService] Disposed');
  }
}

/// Exception thrown when library loading fails
class LibraryLoadException implements Exception {
  final String message;
  const LibraryLoadException(this.message);

  @override
  String toString() => 'LibraryLoadException: $message';
}
