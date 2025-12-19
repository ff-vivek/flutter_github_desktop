import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:gitdesktop/core/git/libgit2_bindings.dart';

/// Type definitions for libgit2 credential structures
///
/// These match the C structures from libgit2:
/// typedef int (*git_cred_acquire_cb)(
///   git_cred **cred,
///   const char *url,
///   const char *username_from_url,
///   unsigned int allowed_types,
///   void *payload
/// );

typedef GitCredAcquireCallback = Int32 Function(
  Pointer<Pointer<Void>> cred,
  Pointer<Utf8> url,
  Pointer<Utf8> usernameFromUrl,
  Uint32 allowedTypes,
  Pointer<Void> payload,
);

typedef GitCredAcquireCallbackDart = int Function(
  Pointer<Pointer<Void>> cred,
  Pointer<Utf8> url,
  Pointer<Utf8> usernameFromUrl,
  int allowedTypes,
  Pointer<Void> payload,
);

/// Credential types supported by libgit2
class GitCredentialType {
  static const int userpassPlaintext = 1 << 0;
  static const int sshKey = 1 << 1;
  static const int sshCustom = 1 << 2;
  static const int defaultCredentials = 1 << 3;
  static const int sshInteractive = 1 << 4;
  static const int username = 1 << 5;
  static const int sshMemory = 1 << 6;
}

/// Information for Git authentication
class GitCredentialInfo {
  final String? personalAccessToken;
  final String? username;
  final String? sshPrivateKeyPath;
  final String? sshPublicKeyPath;
  final String? sshPassphrase;
  const GitCredentialInfo({
    this.personalAccessToken,
    this.username,
    this.sshPrivateKeyPath,
    this.sshPublicKeyPath,
    this.sshPassphrase,
  });
}

/// Provides credentials for Git operations (push, pull, fetch)
///
/// This class creates a C-compatible callback function pointer that libgit2
/// can call when it needs authentication credentials. The callback is registered
/// via git_remote_set_callbacks().
///
/// Flow:
/// 1. Create CredentialsProvider with PAT or SSH key
/// 2. Get callback pointer via getCallbackPointer()
/// 3. Register with git_remote_set_callbacks()
/// 4. When libgit2 needs credentials, it calls the callback
/// 5. Callback supplies PAT or SSH key
/// 6. Git operation continues
///
/// Example:
/// ```dart
/// final provider = CredentialsProvider(
///   personalAccessToken: 'ghp_xxxxxxxxxxxxx',
/// );
///
/// // Pass provider.getCallbackPointer() to git_remote_set_callbacks()
/// // libgit2 will call the callback when pushing/pulling
/// ```
class CredentialsProvider {
  final String? personalAccessToken;
  final String? username; // used for HTTPS username/password or PAT
  final String? sshPrivateKeyPath;
  final String? sshPublicKeyPath;
  final String? sshPassphrase;

  static NativeCallable<GitCredAcquireCallback>? _sharedNativeCallable;
  NativeCallable<GitCredAcquireCallback>? _nativeCallable;

  CredentialsProvider({
    this.personalAccessToken,
    this.username,
    this.sshPrivateKeyPath,
    this.sshPublicKeyPath,
    this.sshPassphrase,
  }) {
    if (personalAccessToken == null &&
        sshPrivateKeyPath == null &&
        sshPublicKeyPath == null) {
      throw ArgumentError('Must provide either PAT or SSH credentials');
    }
  }

  /// Get C-compatible function pointer for libgit2 callback
  ///
  /// IMPORTANT: This uses NativeCallable.isolateLocal(), which means:
  /// - The callback can only be used on the current isolate
  /// - For GitIsolateManager, create the provider ON the background isolate
  /// - Do NOT create it on the main thread and pass to isolate
  Pointer<NativeFunction<GitCredAcquireCallback>> getCallbackPointer() {
    // Create native callable if not already created
    // Note: We use a static callback function to satisfy const requirements
    if (_nativeCallable == null) {
      _nativeCallable = _createNativeCallable();
    }

    return _nativeCallable!.nativeFunction;
  }

  /// Get a static C-compatible function pointer for libgit2 callback.
  /// This can be used across the isolate as it resolves providers via CredentialsRegistry.
  static Pointer<NativeFunction<GitCredAcquireCallback>> getSharedCallbackPointer() {
    _sharedNativeCallable ??= _createNativeCallable();
    return _sharedNativeCallable!.nativeFunction;
  }

  /// Create the native callable with proper exception handling
  static NativeCallable<GitCredAcquireCallback> _createNativeCallable() {
    const errorCode = -1;
    return NativeCallable<GitCredAcquireCallback>.isolateLocal(
      _staticCredentialCallback,
      exceptionalReturn: errorCode, // Return error code on exception
    );
  }

  /// Static callback function for libgit2
  static int _staticCredentialCallback(
    Pointer<Pointer<Void>> cred,
    Pointer<Utf8> url,
    Pointer<Utf8> usernameFromUrl,
    int allowedTypes,
    Pointer<Void> payload,
  ) {
    try {
      // Resolve host from URL for registry lookup
      final urlStr = url.address == 0 ? '' : url.toDartString();
      final userFromUrl = usernameFromUrl.address == 0 ? '' : usernameFromUrl.toDartString();
      final host = _parseHost(urlStr);
      final provider = CredentialsRegistry.resolveForHost(host);
      if (provider == null) {
        debugPrint('[CredentialsProvider] No provider registered for host="$host" url="$urlStr"');
        return -1;
      }

      // Decide which credential to create based on allowed types and provider
      // Prefer HTTPS PAT when available and allowed
      final allowUserpass = (allowedTypes & GitCredentialType.userpassPlaintext) != 0;
      final allowSsh = (allowedTypes & GitCredentialType.sshKey) != 0 || (allowedTypes & GitCredentialType.sshMemory) != 0;

      if (provider.personalAccessToken != null && (allowUserpass || (!allowSsh))) {
        final user = (provider.username ?? userFromUrl).isEmpty ? 'git' : (provider.username ?? userFromUrl);
        final pass = provider.personalAccessToken!;
        return provider._createUsernamePasswordCredential(cred, user, pass);
      }

      if (provider.sshPrivateKeyPath != null && allowSsh) {
        final user = userFromUrl.isNotEmpty ? userFromUrl : 'git';
        return provider._createSshKeyCredential(
          cred,
          user,
          provider.sshPublicKeyPath,
          provider.sshPrivateKeyPath!,
          provider.sshPassphrase ?? '',
        );
      }

      debugPrint('[CredentialsProvider] Allowed types=$allowedTypes but no matching provider fields for host="$host"');
      return -1;
    } catch (e, st) {
      debugPrint('[CredentialsProvider] Callback error: $e\n$st');
      return -1;
    }
  }

  /// Create username/password credential (used for HTTPS with PAT)
  ///
  /// Calls: git_cred_userpass_plaintext_new()
  int _createUsernamePasswordCredential(
    Pointer<Pointer<Void>> cred,
    String username,
    String password,
  ) {
    debugPrint('[CredentialsProvider] Creating userpass credential');
    try {
      final u = username.toNativeUtf8();
      final p = password.toNativeUtf8();
      try {
        final rc = LibGit2Bindings.I.cred_userpass_plaintext_new(cred.cast(), u, p);
        return rc;
      } finally {
        malloc.free(u);
        malloc.free(p);
      }
    } catch (e) {
      debugPrint('[CredentialsProvider] userpass credential error: $e');
      return -1;
    }
  }

  /// Create SSH key credential
  ///
  /// Calls: git_cred_ssh_key_new()
  int _createSshKeyCredential(
    Pointer<Pointer<Void>> cred,
    String username,
    String? publicKeyPath,
    String privateKeyPath,
    String passphrase,
  ) {
    debugPrint('[CredentialsProvider] Creating SSH key credential');
    try {
      final u = username.toNativeUtf8();
      final pub = publicKeyPath != null ? publicKeyPath.toNativeUtf8() : Pointer<Utf8>.fromAddress(0);
      final priv = privateKeyPath.toNativeUtf8();
      final pass = passphrase.toNativeUtf8();
      try {
        final rc = LibGit2Bindings.I.cred_ssh_key_new(cred.cast(), u, pub, priv, pass);
        return rc;
      } finally {
        malloc.free(u);
        if (pub.address != 0) malloc.free(pub);
        malloc.free(priv);
        malloc.free(pass);
      }
    } catch (e) {
      debugPrint('[CredentialsProvider] ssh credential error: $e');
      return -1;
    }
  }

  /// Cleanup the native callable
  void dispose() {
    _nativeCallable?.close();
    _nativeCallable = null;
    debugPrint('[CredentialsProvider] Disposed');
  }
}

/// Factory for creating CredentialsProvider instances
///
/// In production, this would fetch credentials from secure storage
/// (flutter_secure_storage) or system keychain.
class CredentialsFactory {
  /// Create provider with Personal Access Token
  static Future<CredentialsProvider> createWithPAT(String token, {String? username}) async {
    // TODO: Validate token format
    return CredentialsProvider(personalAccessToken: token, username: username);
  }

  /// Create provider with SSH key
  static Future<CredentialsProvider> createWithSSH({
    required String privateKeyPath,
    String? publicKeyPath,
    String? passphrase,
  }) async {
    // TODO: Validate key files exist
    return CredentialsProvider(
      sshPrivateKeyPath: privateKeyPath,
      sshPublicKeyPath: publicKeyPath,
      sshPassphrase: passphrase,
    );
  }

  /// Load credentials from secure storage
  ///
  /// This would use flutter_secure_storage to retrieve saved credentials
  static Future<CredentialsProvider?> loadFromSecureStorage(String repoUrl) async {
    // TODO: Implement secure storage integration
    // final storage = FlutterSecureStorage();
    // final token = await storage.read(key: 'git_pat_$repoUrl');
    // if (token != null) {
    //   return createWithPAT(token);
    // }
    debugPrint('[CredentialsFactory] Secure storage integration pending');
    return null;
  }

  /// Save credentials to secure storage
  static Future<void> saveToSecureStorage(
    String repoUrl,
    String token,
  ) async {
    // TODO: Implement secure storage integration
    // final storage = FlutterSecureStorage();
    // await storage.write(key: 'git_pat_$repoUrl', value: token);
    debugPrint('[CredentialsFactory] Secure storage integration pending');
  }
}

/// In-memory session registry for credentials, keyed by host.
/// This is isolate-local and intentionally ephemeral.
class CredentialsRegistry {
  static final Map<String, CredentialsProvider> _byHost = <String, CredentialsProvider>{};
  static CredentialsProvider? _global;

  /// Registers a provider for a specific host (e.g., github.com).
  static void registerForHost(String host, CredentialsProvider provider) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) return;
    _byHost[key] = provider;
    debugPrint('[CredentialsRegistry] Registered provider for host="$key"');
  }

  /// Registers a global fallback provider used when no host-specific entry exists.
  static void registerGlobal(CredentialsProvider provider) {
    _global = provider;
    debugPrint('[CredentialsRegistry] Registered global credentials provider');
  }

  /// Resolves the best provider for a URL or host.
  static CredentialsProvider? resolveForUrl(String url) => resolveForHost(_parseHost(url));

  static CredentialsProvider? resolveForHost(String host) {
    final key = host.trim().toLowerCase();
    final p = _byHost[key];
    return p ?? _global;
  }

  /// Exports all current credentials for transport to background isolate.
  static Map<String, GitCredentialInfo> exportAll() {
    final results = <String, GitCredentialInfo>{};
    _byHost.forEach((host, p) {
      results[host] = GitCredentialInfo(
        personalAccessToken: p.personalAccessToken,
        username: p.username,
        sshPrivateKeyPath: p.sshPrivateKeyPath,
        sshPublicKeyPath: p.sshPublicKeyPath,
        sshPassphrase: p.sshPassphrase,
      );
    });
    // Add global as a special key if present
    if (_global != null) {
      final g = _global!;
      results['*'] = GitCredentialInfo(
        personalAccessToken: g.personalAccessToken,
        username: g.username,
        sshPrivateKeyPath: g.sshPrivateKeyPath,
        sshPublicKeyPath: g.sshPublicKeyPath,
        sshPassphrase: g.sshPassphrase,
      );
    }
    return results;
  }
}

String _parseHost(String url) {
  if (url.isEmpty) return '';
  try {
    if (url.contains('://')) {
      final u = Uri.parse(url);
      return u.host;
    }
    final at = url.indexOf('@');
    final colon = url.indexOf(':');
    if (at != -1 && colon != -1 && colon > at) {
      return url.substring(at + 1, colon);
    }
  } catch (_) {}
  return '';
}
