import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:gitdesktop/core/git/dynamic_library_service.dart';

/// Opaque C structs
final class git_repository extends Opaque {}
final class git_status_list extends Opaque {}
final class git_commit extends Opaque {}
final class git_tree extends Opaque {}
final class git_tree_entry extends Opaque {}
final class git_blob extends Opaque {}
final class git_object extends Opaque {}
final class git_index extends Opaque {}
final class git_signature extends Struct {
    external Pointer<Int8> name;
    external Pointer<Int8> email;
    @Int64()
    external int when_time;
    @Int32()
    external int when_offset;
  }
  final class git_revwalk extends Opaque {}
  final class git_remote extends Opaque {}
  final class git_reference extends Opaque {}
  final class git_transfer_progress extends Struct {
    @Uint32()
    external int total_objects;
    @Uint32()
    external int indexed_objects;
    @Uint32()
    external int received_objects;
    @Uint32()
    external int local_objects;
    @Uint32()
    external int total_deltas;
    @Uint32()
    external int indexed_deltas;
    @Uint64()
    external int received_bytes;
  }

  /// git_error from libgit2 (readonly from git_error_last)
  /// typedef struct {
  ///   int klass;
  ///   const char *message;
  /// } git_error;
  final class git_error extends Struct {
    @Int32()
    external int klass;
    external Pointer<Int8> message;
  }

/// Callback: int (*git_status_cb)(const char *path, unsigned int status_flags, void *payload)
typedef GitStatusCbNative = Int32 Function(Pointer<Utf8> path, Uint32 statusFlags, Pointer<Void> payload);
typedef GitStatusCbDart = int Function(Pointer<Utf8> path, int statusFlags, Pointer<Void> payload);

/// Callback for diff lines: int (*git_diff_line_cb)(const git_diff_delta*, const git_diff_hunk*, const git_diff_line*, void*)
typedef GitDiffLineCbNative = Int32 Function(Pointer<Void> delta, Pointer<Void> hunk, Pointer<git_diff_line> line, Pointer<Void> payload);
typedef GitDiffLineCbDart = int Function(Pointer<Void> delta, Pointer<Void> hunk, Pointer<git_diff_line> line, Pointer<Void> payload);

/// Callback for credentials: int (*git_cred_acquire_cb)(git_cred **cred, const char *url, const char *username_from_url, unsigned int allowed_types, void *payload)
typedef GitCredAcquireCbNative = Int32 Function(Pointer<Pointer<Void>> cred, Pointer<Utf8> url, Pointer<Utf8> usernameFromUrl, Uint32 allowedTypes, Pointer<Void> payload);

/// Callback for transfer progress: int (*git_transfer_progress_cb)(const git_transfer_progress *stats, void *payload)
typedef GitTransferProgressCbNative = Int32 Function(Pointer<git_transfer_progress> stats, Pointer<Void> payload);

/// Callback for sideband progress: int (*git_transport_message_cb)(const char *str, int len, void *payload)
typedef GitSidebandProgressCbNative = Int32 Function(Pointer<Int8> str, Int32 len, Pointer<Void> payload);

/// git_oid (20-byte SHA1-ish) structure
final class git_oid extends Struct {
  @Array(20)
  external Array<Uint8> id;
}

/// git_diff_line structure (subset we use)
/// typedef struct {
///   char origin;
///   int old_lineno;
///   int new_lineno;
///   int num_lines;
///   size_t content_len;
///   const char *content;
///   git_off_t content_offset;
/// } git_diff_line;
final class git_diff_line extends Struct {
  @Int8()
  external int origin;

  @Int32()
  external int old_lineno;

  @Int32()
  external int new_lineno;

  @Int32()
  external int num_lines;

  @Uint64()
  external int content_len;

  external Pointer<Int8> content;

  @Int64()
  external int content_offset;
}

/// git_strarray { char **strings; size_t count; }
final class git_strarray extends Struct {
  external Pointer<Pointer<Int8>> strings;
  @Uint64()
  external int count;
}

/// git_remote_callbacks
final class git_remote_callbacks extends Struct {
  @Uint32()
  external int version;

  external Pointer<NativeFunction<GitSidebandProgressCbNative>> sideband_progress;
  external Pointer<Void> certificate_check; // git_transport_certificate_check_cb
  external Pointer<NativeFunction<GitTransferProgressCbNative>> transfer_progress;
  external Pointer<Void> push_update_reference; // git_push_update_reference_cb
  external Pointer<Void> push_transfer_progress; // git_push_transfer_progress_cb
  external Pointer<Void> push_negotiation; // git_push_negotiation_cb
  external Pointer<Void> transport_message; // git_transport_message_cb
  external Pointer<Void> url_resolve; // git_url_resolve_cb
  external Pointer<NativeFunction<GitCredAcquireCbNative>> credentials;

  external Pointer<Void> payload;
}

/// git_fetch_options
final class git_fetch_options extends Struct {
  @Uint32()
  external int version;

  external git_remote_callbacks callbacks;

  @Int32()
  external int prune;

  @Int32()
  external int update_fetchhead;

  @Int32()
  external int download_tags;

  // Simplified proxy_opts and custom_headers for now
  @Array(64) // proxy_opts (approx size if we don't use it)
  external Array<Uint8> proxy_opts;

  external git_strarray custom_headers;
}

/// git_push_options
final class git_push_options extends Struct {
  @Uint32()
  external int version;

  @Uint32()
  external int pb_parallelism;

  external git_remote_callbacks callbacks;

  // proxy_opts and custom_headers
  @Array(64)
  external Array<Uint8> proxy_opts;

  external git_strarray custom_headers;
}

/// Minimal libgit2 bindings needed for Phase 1 (open repo + status)
class LibGit2Bindings {
  static LibGit2Bindings? _instance;
  final DynamicLibrary _lib;

  // Function refs
  late final int Function() libgit2_init;
  late final void Function() libgit2_shutdown;
  late final int Function(Pointer<Pointer<git_repository>> out, Pointer<Utf8> path) repository_open;
  late final void Function(Pointer<git_repository>) repository_free;
  late final int Function(Pointer<git_repository>, Pointer<NativeFunction<GitStatusCbNative>>, Pointer<Void>) status_foreach;

  // Additional refs for diff & blobs
  late final int Function(Pointer<git_oid> out, Pointer<git_repository> repo, Pointer<Utf8> name) reference_name_to_id;
  late final int Function(Pointer<Pointer<git_commit>> out, Pointer<git_repository> repo, Pointer<git_oid> id) commit_lookup;
  late final void Function(Pointer<git_commit>) commit_free;
  late final Pointer<Utf8> Function(Pointer<git_commit>) commit_message;
  late final Pointer<git_signature> Function(Pointer<git_commit>) commit_author;
  late final int Function(Pointer<git_commit>) commit_time;
  late final int Function(Pointer<Pointer<git_tree>> out, Pointer<git_commit> commit) commit_tree;
  late final void Function(Pointer<git_tree>) tree_free;
  late final int Function(Pointer<Pointer<git_tree_entry>> out, Pointer<git_tree> root, Pointer<Utf8> path) tree_entry_bypath;
  late final void Function(Pointer<git_tree_entry>) tree_entry_free;
  late final Pointer<git_oid> Function(Pointer<git_tree_entry> entry) tree_entry_id;
  late final int Function(Pointer<Pointer<git_blob>> out, Pointer<git_repository> repo, Pointer<git_oid> id) blob_lookup;
  late final int Function(Pointer<Pointer<git_blob>> out, Pointer<git_repository> repo, Pointer<Utf8> path) blob_create_fromworkdir;
  late final void Function(Pointer<git_blob>) blob_free;
  late final int Function(
    Pointer<git_blob> oldBlob,
    Pointer<Utf8> oldAsPath,
    Pointer<git_blob> newBlob,
    Pointer<Utf8> newAsPath,
    Pointer<Void> options,
    Pointer<Void> fileCb,
    Pointer<Void> binaryCb,
    Pointer<Void> hunkCb,
    Pointer<NativeFunction<GitDiffLineCbNative>> lineCb,
    Pointer<Void> payload,
  ) diff_blobs;

    // Index APIs (staging)
    late final int Function(Pointer<Pointer<git_index>> out, Pointer<git_repository> repo) repository_index;
    late final void Function(Pointer<git_index> index) index_free;
    late final int Function(Pointer<git_index> index, Pointer<Utf8> path) index_add_bypath;
    late final int Function(Pointer<git_index> index) index_write;
    late final int Function(Pointer<git_oid> out, Pointer<git_index> index) index_write_tree;

    // Tree lookup (after write_tree)
    late final int Function(Pointer<Pointer<git_tree>> out, Pointer<git_repository> repo, Pointer<git_oid> id) tree_lookup;

    // Signature + commit
    late final int Function(Pointer<Pointer<git_signature>> out, Pointer<Utf8> name, Pointer<Utf8> email) signature_now;
    late final void Function(Pointer<git_signature> sig) signature_free;
    late final int Function(
      Pointer<git_oid> out,
      Pointer<git_repository> repo,
      Pointer<Utf8> updateRef,
      Pointer<git_signature> author,
      Pointer<git_signature> committer,
      Pointer<Void> messageEncoding,
      Pointer<Utf8> message,
      Pointer<git_tree> tree,
      int parentCount,
      Pointer<Pointer<git_commit>> parents,
    ) commit_create;

  // Revwalk (history)
  late final int Function(Pointer<Pointer<git_revwalk>> out, Pointer<git_repository> repo) revwalk_new;
  late final void Function(Pointer<git_revwalk> walk) revwalk_free;
  late final void Function(Pointer<git_revwalk> walk, int sortMode) revwalk_sorting;
  late final int Function(Pointer<git_revwalk> walk) revwalk_push_head;
  late final int Function(Pointer<git_oid> out, Pointer<git_revwalk> walk) revwalk_next;

  // Remotes
  late final int Function(Pointer<git_strarray> out, Pointer<git_repository> repo) remote_list;
  late final int Function(Pointer<Pointer<git_remote>> out, Pointer<git_repository> repo, Pointer<Utf8> name) remote_lookup;
  late final Pointer<Utf8> Function(Pointer<git_remote> remote) remote_url;
  late final void Function(Pointer<git_remote> remote) remote_free;
  late final int Function(Pointer<Pointer<git_remote>> out, Pointer<git_repository> repo, Pointer<Utf8> name, Pointer<Utf8> url) remote_create;
  late final int Function(Pointer<git_repository> repo, Pointer<Utf8> name) remote_delete;
  late final int Function(Pointer<git_repository> repo, Pointer<Utf8> name, Pointer<Utf8> url) remote_set_url;
  // Network
  // int git_remote_connect(git_remote *remote, git_direction direction, const git_remote_callbacks *callbacks, const git_proxy_options *proxy_opts, const git_strarray *custom_headers);
  late final int Function(Pointer<git_remote> remote, int direction, Pointer<git_remote_callbacks> callbacks, Pointer<Void> proxyOpts, Pointer<git_strarray> customHeaders) remote_connect;
  // int git_remote_connected(const git_remote *remote);
  late final int Function(Pointer<git_remote> remote) remote_connected;
  // void git_remote_disconnect(git_remote *remote);
  late final void Function(Pointer<git_remote> remote) remote_disconnect;
  // int git_remote_fetch(git_remote *remote, const git_strarray *refspecs, const git_fetch_options *opts, const char *reflog_message);
  late final int Function(Pointer<git_remote> remote, Pointer<git_strarray> refspecs, Pointer<git_fetch_options> opts, Pointer<Utf8> reflogMessage) remote_fetch;
  late final void Function(Pointer<git_strarray> arr) strarray_dispose;
  // int git_remote_push(git_remote *remote, const git_strarray *refspecs, const git_push_options *opts);
  late final int Function(Pointer<git_remote> remote, Pointer<git_strarray> refspecs, Pointer<git_push_options> opts) remote_push;
  // int git_fetch_init_options(git_fetch_options *opts, unsigned int version);
  late final int Function(Pointer<git_fetch_options> opts, int version) fetch_init_options;
  // int git_push_init_options(git_push_options *opts, unsigned int version);
  late final int Function(Pointer<git_push_options> opts, int version) push_init_options;
  // int git_remote_init_callbacks(git_remote_callbacks *opts, unsigned int version);
  late final int Function(Pointer<git_remote_callbacks> opts, int version) remote_init_callbacks;
  // const git_transfer_progress * git_remote_stats(git_remote *remote)
  late final Pointer<git_transfer_progress> Function(Pointer<git_remote> remote) remote_stats;
  // Credentials helpers
  // int git_cred_userpass_plaintext_new(git_cred **out, const char *username, const char *password);
  late final int Function(Pointer<Pointer<Void>> out, Pointer<Utf8> username, Pointer<Utf8> password) cred_userpass_plaintext_new;
  // int git_cred_ssh_key_new(git_cred **out, const char *username, const char *publickey, const char *privatekey, const char *passphrase);
  late final int Function(Pointer<Pointer<Void>> out, Pointer<Utf8> username, Pointer<Utf8> publickey, Pointer<Utf8> privatekey, Pointer<Utf8> passphrase) cred_ssh_key_new;

  // Errors
  // const git_error * git_error_last(void);
  late final Pointer<git_error> Function() error_last;

  // HEAD / references
  late final int Function(Pointer<Pointer<git_reference>> out, Pointer<git_repository> repo) repository_head;
  late final void Function(Pointer<git_reference> reference) reference_free;
  late final Pointer<Utf8> Function(Pointer<git_reference> reference) reference_name;
  // Branch upstream helpers
  // int git_branch_upstream(git_reference **out, const git_reference *branch)
  late final int Function(Pointer<Pointer<git_reference>> out, Pointer<git_reference> branch) branch_upstream;
  // int git_branch_set_upstream(git_reference *branch, const char *upstream_name)
  late final int Function(Pointer<git_reference> branch, Pointer<Utf8> upstreamName) branch_set_upstream;

  // Merge / reset helpers
  // int git_merge_base(git_oid *out, git_repository *repo, const git_oid *one, const git_oid *two);
  late final int Function(Pointer<git_oid> out, Pointer<git_repository> repo, Pointer<git_oid> one, Pointer<git_oid> two) merge_base;
  // int git_reset(git_repository *repo, const git_object *target, int reset_type, const git_checkout_options *opts);
  late final int Function(Pointer<git_repository> repo, Pointer<git_object> target, int resetType, Pointer<Void> opts) reset;

  LibGit2Bindings._(this._lib) {
    libgit2_init = _lib.lookup<NativeFunction<Int32 Function()>>('git_libgit2_init').asFunction();
    libgit2_shutdown = _lib.lookup<NativeFunction<Void Function()>>('git_libgit2_shutdown').asFunction();
    repository_open = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_repository>>, Pointer<Utf8>)>>('git_repository_open')
        .asFunction();
    repository_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_repository>)>>('git_repository_free')
        .asFunction();
    status_foreach = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_repository>, Pointer<NativeFunction<GitStatusCbNative>>, Pointer<Void>)>>('git_status_foreach')
        .asFunction();

    // Extended lookups
    reference_name_to_id = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_oid>, Pointer<git_repository>, Pointer<Utf8>)>>('git_reference_name_to_id')
        .asFunction();
    commit_lookup = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_commit>>, Pointer<git_repository>, Pointer<git_oid>)>>('git_commit_lookup')
        .asFunction();
    commit_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_commit>)>>('git_commit_free')
        .asFunction();
    commit_message = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<git_commit>)>>('git_commit_message')
        .asFunction();
    commit_author = _lib
        .lookup<NativeFunction<Pointer<git_signature> Function(Pointer<git_commit>)>>('git_commit_author')
        .asFunction();
    commit_time = _lib
        .lookup<NativeFunction<Int64 Function(Pointer<git_commit>)>>('git_commit_time')
        .asFunction();
    commit_tree = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_tree>>, Pointer<git_commit>)>>('git_commit_tree')
        .asFunction();
    tree_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_tree>)>>('git_tree_free')
        .asFunction();
    tree_entry_bypath = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_tree_entry>>, Pointer<git_tree>, Pointer<Utf8>)>>('git_tree_entry_bypath')
        .asFunction();
    tree_entry_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_tree_entry>)>>('git_tree_entry_free')
        .asFunction();
    tree_entry_id = _lib
        .lookup<NativeFunction<Pointer<git_oid> Function(Pointer<git_tree_entry>)>>('git_tree_entry_id')
        .asFunction();
    blob_lookup = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_blob>>, Pointer<git_repository>, Pointer<git_oid>)>>('git_blob_lookup')
        .asFunction();
    blob_create_fromworkdir = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_blob>>, Pointer<git_repository>, Pointer<Utf8>)>>('git_blob_create_fromworkdir')
        .asFunction();
    blob_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_blob>)>>('git_blob_free')
        .asFunction();
    diff_blobs = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<git_blob>,
                  Pointer<Utf8>,
                  Pointer<git_blob>,
                  Pointer<Utf8>,
                  Pointer<Void>,
                  Pointer<Void>,
                  Pointer<Void>,
                  Pointer<Void>,
                  Pointer<NativeFunction<GitDiffLineCbNative>>,
                  Pointer<Void>,
                )
              >
          >('git_diff_blobs')
        .asFunction();

    // Index
    repository_index = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_index>>, Pointer<git_repository>)>>('git_repository_index')
        .asFunction();
    index_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_index>)>>('git_index_free')
        .asFunction();
    index_add_bypath = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_index>, Pointer<Utf8>)>>('git_index_add_bypath')
        .asFunction();
    index_write = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_index>)>>('git_index_write')
        .asFunction();
    index_write_tree = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_oid>, Pointer<git_index>)>>('git_index_write_tree')
        .asFunction();

    // Tree lookup
    tree_lookup = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_tree>>, Pointer<git_repository>, Pointer<git_oid>)>>('git_tree_lookup')
        .asFunction();

    // Signature + commit
    signature_now = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_signature>>, Pointer<Utf8>, Pointer<Utf8>)>>('git_signature_now')
        .asFunction();
    signature_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_signature>)>>('git_signature_free')
        .asFunction();
    commit_create = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<git_oid>,
                  Pointer<git_repository>,
                  Pointer<Utf8>,
                  Pointer<git_signature>,
                  Pointer<git_signature>,
                  Pointer<Void>,
                  Pointer<Utf8>,
                  Pointer<git_tree>,
                  Int32,
                  Pointer<Pointer<git_commit>>,
                )
              >
          >('git_commit_create')
        .asFunction();

    // Revwalk
    revwalk_new = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_revwalk>>, Pointer<git_repository>)>>('git_revwalk_new')
        .asFunction();
    revwalk_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_revwalk>)>>('git_revwalk_free')
        .asFunction();
    revwalk_sorting = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_revwalk>, Int32)>>('git_revwalk_sorting')
        .asFunction();
    revwalk_push_head = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_revwalk>)>>('git_revwalk_push_head')
        .asFunction();
    revwalk_next = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_oid>, Pointer<git_revwalk>)>>('git_revwalk_next')
        .asFunction();

    // Remotes
    remote_list = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_strarray>, Pointer<git_repository>)>>('git_remote_list')
        .asFunction();
    remote_lookup = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_remote>>, Pointer<git_repository>, Pointer<Utf8>)>>('git_remote_lookup')
        .asFunction();
    remote_url = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<git_remote>)>>('git_remote_url')
        .asFunction();
    remote_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_remote>)>>('git_remote_free')
        .asFunction();
    remote_create = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_remote>>, Pointer<git_repository>, Pointer<Utf8>, Pointer<Utf8>)>>('git_remote_create')
        .asFunction();
    remote_delete = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_repository>, Pointer<Utf8>)>>('git_remote_delete')
        .asFunction();
    remote_set_url = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_repository>, Pointer<Utf8>, Pointer<Utf8>)>>('git_remote_set_url')
        .asFunction();
    remote_connect = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<git_remote>,
                  Int32,
                  Pointer<git_remote_callbacks>,
                  Pointer<Void>,
                  Pointer<git_strarray>,
                )
              >
          >('git_remote_connect')
        .asFunction();
    remote_connected = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_remote>)>>('git_remote_connected')
        .asFunction();
    remote_disconnect = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_remote>)>>('git_remote_disconnect')
        .asFunction();
    remote_fetch = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_remote>, Pointer<git_strarray>, Pointer<git_fetch_options>, Pointer<Utf8>)>>('git_remote_fetch')
        .asFunction();
    remote_push = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_remote>, Pointer<git_strarray>, Pointer<git_push_options>)>>('git_remote_push')
        .asFunction();
    fetch_init_options = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_fetch_options>, Uint32)>>('git_fetch_options_init')
        .asFunction();
    push_init_options = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_push_options>, Uint32)>>('git_push_options_init')
        .asFunction();
    remote_init_callbacks = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_remote_callbacks>, Uint32)>>('git_remote_init_callbacks')
        .asFunction();
    remote_stats = _lib
        .lookup<NativeFunction<Pointer<git_transfer_progress> Function(Pointer<git_remote>)>>('git_remote_stats')
        .asFunction();
    strarray_dispose = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_strarray>)>>('git_strarray_dispose')
        .asFunction();
    // Credentials helpers
    cred_userpass_plaintext_new = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>, Pointer<Utf8>)>>('git_cred_userpass_plaintext_new')
        .asFunction();
    cred_ssh_key_new = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>>('git_cred_ssh_key_new')
        .asFunction();

    // Errors
    error_last = _lib
        .lookup<NativeFunction<Pointer<git_error> Function()>>('git_error_last')
        .asFunction();

    // HEAD / references
    repository_head = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_reference>>, Pointer<git_repository>)>>('git_repository_head')
        .asFunction();
    reference_free = _lib
        .lookup<NativeFunction<Void Function(Pointer<git_reference>)>>('git_reference_free')
        .asFunction();
    reference_name = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<git_reference>)>>('git_reference_name')
        .asFunction();
    branch_upstream = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Pointer<git_reference>>, Pointer<git_reference>)>>('git_branch_upstream')
        .asFunction();
    branch_set_upstream = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_reference>, Pointer<Utf8>)>>('git_branch_set_upstream')
        .asFunction();

    // Merge / reset
    merge_base = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_oid>, Pointer<git_repository>, Pointer<git_oid>, Pointer<git_oid>)>>('git_merge_base')
        .asFunction();
    reset = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<git_repository>, Pointer<git_object>, Int32, Pointer<Void>)>>('git_reset')
        .asFunction();
  }

  static LibGit2Bindings get I {
    final existing = _instance;
    if (existing != null) return existing;
    if (!DynamicLibraryService.isLoaded) {
      throw StateError('Dynamic library not loaded. Call DynamicLibraryService.initialize() first.');
    }
    _instance = LibGit2Bindings._(DynamicLibraryService.library);
    return _instance!;
  }

  /// Convenience helpers
  static Pointer<Utf8> toUtf8(String s) => s.toNativeUtf8();

  /// Reads the last libgit2 error if available.
  static GitErrorInfo? lastError() {
    try {
      final p = I.error_last();
      if (p.address == 0) return null;
      final msgPtr = p.ref.message;
      final msg = msgPtr.address == 0 ? '' : msgPtr.cast<Utf8>().toDartString();
      return GitErrorInfo(p.ref.klass, msg);
    } catch (_) {
      return null;
    }
  }
}

/// Status flag constants (subset)
/// Mirrors libgit2 git_status_t values
class GitStatusFlags {
  static const int indexNew = 1 << 0; // GIT_STATUS_INDEX_NEW
  static const int indexModified = 1 << 1; // GIT_STATUS_INDEX_MODIFIED
  static const int indexDeleted = 1 << 2; // GIT_STATUS_INDEX_DELETED
  static const int indexRenamed = 1 << 3; // GIT_STATUS_INDEX_RENAMED
  static const int indexTypeChange = 1 << 4; // GIT_STATUS_INDEX_TYPECHANGE

  static const int wtNew = 1 << 7; // GIT_STATUS_WT_NEW
  static const int wtModified = 1 << 8; // GIT_STATUS_WT_MODIFIED
  static const int wtDeleted = 1 << 9; // GIT_STATUS_WT_DELETED
  static const int wtTypeChange = 1 << 10; // GIT_STATUS_WT_TYPECHANGE
  static const int wtRenamed = 1 << 11; // GIT_STATUS_WT_RENAMED
  static const int ignored = 1 << 14; // GIT_STATUS_IGNORED
  static const int conflicted = 1 << 15; // GIT_STATUS_CONFLICTED
}

/// Revwalk sorting flags (subset)
class GitSortMode {
  static const int none = 0;
  static const int topological = 1; // GIT_SORT_TOPOLOGICAL
  static const int time = 2; // GIT_SORT_TIME
  static const int reverse = 4; // GIT_SORT_REVERSE
}

/// Container for libgit2 error info
class GitErrorInfo {
  final int klass;
  final String message;
  const GitErrorInfo(this.klass, this.message);
}
