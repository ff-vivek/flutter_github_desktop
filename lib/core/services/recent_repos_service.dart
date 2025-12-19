import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Model representing a recently opened repository
class RecentRepo {
  final String path;
  final String name;
  final DateTime lastOpened;

  const RecentRepo({required this.path, required this.name, required this.lastOpened});

  RecentRepo copyWith({String? path, String? name, DateTime? lastOpened}) => RecentRepo(
        path: path ?? this.path,
        name: name ?? this.name,
        lastOpened: lastOpened ?? this.lastOpened,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory RecentRepo.fromJson(Map<String, dynamic> json) => RecentRepo(
        path: json['path'] as String,
        name: json['name'] as String,
        lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Storage + business logic for recent repositories (web/desktop safe)
class RecentReposStore {
  static const _prefsKey = 'recent_repos_v1';

  /// Load recent repos from persistent storage
  static Future<List<RecentRepo>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded = json.decode(raw);
      if (decoded is! List) return [];

      final result = <RecentRepo>[];
      for (final item in decoded) {
        try {
          result.add(RecentRepo.fromJson(Map<String, dynamic>.from(item as Map)));
        } catch (e) {
          debugPrint('[RecentReposStore] Skipping invalid entry: $e');
        }
      }

      // Auto-sanitize by writing back a clean list
      await _save(result);
      return result;
    } catch (e) {
      debugPrint('[RecentReposStore] Failed to load recent repos: $e');
      return [];
    }
  }

  /// Save recent repos list
  static Future<void> _save(List<RecentRepo> repos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = json.encode(repos.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, payload);
    } catch (e) {
      debugPrint('[RecentReposStore] Failed to save recent repos: $e');
    }
  }

  /// Add or update a repo entry; newest first; max 20
  static Future<List<RecentRepo>> addOrUpdate(String path) async {
    final repos = await load();
    final name = p.basename(path);
    final now = DateTime.now();
    final existingIndex = repos.indexWhere((r) => r.path == path);
    if (existingIndex >= 0) {
      final updated = repos[existingIndex].copyWith(lastOpened: now, name: name);
      repos.removeAt(existingIndex);
      repos.insert(0, updated);
    } else {
      repos.insert(0, RecentRepo(path: path, name: name, lastOpened: now));
    }
    final trimmed = repos.take(20).toList();
    await _save(trimmed);
    return trimmed;
  }

  /// Remove a repo by path
  static Future<List<RecentRepo>> remove(String path) async {
    final repos = await load();
    repos.removeWhere((r) => r.path == path);
    await _save(repos);
    return repos;
  }

  /// Clear all
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('[RecentReposStore] Failed to clear: $e');
    }
  }
}

/// Riverpod AsyncNotifier for recent repos list
class RecentReposNotifier extends AsyncNotifier<List<RecentRepo>> {
  @override
  Future<List<RecentRepo>> build() async {
    try {
      return await RecentReposStore.load();
    } catch (e) {
      debugPrint('[RecentReposNotifier] build failed: $e');
      return [];
    }
  }

  Future<void> addOrUpdate(String path) async {
    state = const AsyncValue.loading();
    try {
      final updated = await RecentReposStore.addOrUpdate(path);
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('[RecentReposNotifier] addOrUpdate failed: $e');
      state = AsyncValue.data(state.asData?.value ?? []);
    }
  }

  Future<void> remove(String path) async {
    state = const AsyncValue.loading();
    try {
      final updated = await RecentReposStore.remove(path);
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('[RecentReposNotifier] remove failed: $e');
      state = AsyncValue.data(state.asData?.value ?? []);
    }
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    try {
      final items = await RecentReposStore.load();
      state = AsyncValue.data(items);
    } catch (e) {
      debugPrint('[RecentReposNotifier] reload failed: $e');
      state = AsyncValue.data(state.asData?.value ?? []);
    }
  }
}

final recentReposProvider = AsyncNotifierProvider<RecentReposNotifier, List<RecentRepo>>(RecentReposNotifier.new);
