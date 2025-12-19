# GitHub Desktop Clone - Architecture

## Overview
A GitHub Desktop clone built with Flutter using `dart:ffi` to interface with `libgit2` for native Git operations. The app emphasizes performance, thread safety, and a modern UI.

## Technology Stack
- **Frontend**: Flutter (cross-platform: Windows, macOS, Linux, Web)
- **State Management**: Riverpod
- **Native Git Operations**: `dart:ffi` + `libgit2`
- **Navigation**: go_router
- **File Watching**: package:watcher
- **Fonts**: Google Fonts (Inter)

## Critical Technical Risks & Solutions

### 1. Concurrency (FFI on Background Isolates)
**Risk**: FFI calls block the UI thread, causing jank and freezing.

**Solution**: `GitIsolateManager`
- All `libgit2` FFI calls execute on a dedicated background Isolate
- Main thread sends commands via `SendPort` and receives results via `ReceivePort`
- Commands are queued and processed sequentially to avoid race conditions
- Result is marshaled back as pure Dart objects (no pointers cross isolate boundaries)

**Flow**:
```
UI Thread → GitIsolateManager.execute() 
         → SendPort (message) 
         → Background Isolate (FFI calls) 
         → ReceivePort (result) 
         → Future completes
```

### 2. Authentication (Callbacks to Dart from C)
**Risk**: `libgit2` requires C callbacks for credentials, but Dart functions can't be directly passed to C.

**Solution**: `CredentialsProvider`
- Use `NativeCallable.isolateLocal()` to create a C-compatible function pointer
- Register the callback with `git_remote_set_callbacks()`
- When `libgit2` requests credentials, the callback supplies a Personal Access Token
- Credentials are stored securely (platform keychain integration via `flutter_secure_storage`)

**Flow**:
```
git_remote_fetch() → libgit2 needs creds 
                  → C callback (NativeCallable) 
                  → Dart function 
                  → Return PAT
```

### 3. Native Binary Management
**Risk**: Different platforms require different shared libraries.

**Solution**: `DynamicLibraryService`
- Conditionally loads the correct `libgit2` binary:
  - Windows: `libgit2.dll`
  - macOS: `libgit2.dylib`
  - Linux: `libgit2.so`
- Bundles binaries in platform-specific asset directories
- Falls back to system library if bundled version not found
- Exposes FFI bindings globally via singleton

### 4. Diff Rendering (Safe Pointer Marshaling)
**Risk**: Raw FFI pointers can't be used in UI; must be converted to Dart objects.

**Solution**: `DiffHunk` and `DiffLine` models
- Pure Dart data classes with no FFI dependencies
- `DiffParser` service walks `git_diff` pointers on background isolate
- Converts to `List<DiffHunk>` containing `List<DiffLine>`
- UI safely renders the diff without touching pointers
- Supports syntax highlighting via metadata (line type: added/deleted/context)

**Flow**:
```
git_diff_foreach() → FFI pointers (background isolate) 
                   → DiffParser.parse() 
                   → List<DiffHunk> (pure Dart) 
                   → UI renders
```

### 5. State Management (Debounced File Watching)
**Risk**: Rapid file changes trigger excessive Git status checks, causing performance issues.

**Solution**: `RepositoryStateNotifier` (Riverpod)
- Listens to filesystem events via `package:watcher`
- Implements 500ms debounce timer
- Only triggers `git status` after file edits settle
- Notifies UI of repository state changes (modified files, staged files, etc.)
- Cancels pending timers when new events arrive

**Flow**:
```
File change → Watcher event 
            → Debounce 500ms 
            → git status (background isolate) 
            → RepositoryState 
            → UI updates
```

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── theme.dart                         # Custom theme (no Material Design)
├── nav.dart                           # go_router configuration
│
├── core/
│   ├── git/
│   │   ├── git_isolate_manager.dart   # Background isolate manager
│   │   ├── dynamic_library_service.dart # Platform-specific binary loading
│   │   ├── ffi_bindings.dart          # FFI function signatures
│   │   └── credentials_provider.dart  # Authentication callbacks
│   │
│   ├── models/
│   │   ├── repository.dart            # Repository metadata
│   │   ├── commit.dart                # Commit info
│   │   ├── branch.dart                # Branch info
│   │   ├── diff_hunk.dart             # Diff hunk model
│   │   ├── diff_line.dart             # Diff line model
│   │   └── file_status.dart           # File status (modified, staged, etc.)
│   │
│   ├── services/
│   │   ├── repository_service.dart    # Git operations (clone, status, commit)
│   │   ├── diff_parser.dart           # Parse FFI diffs to Dart objects
│   │   └── credentials_service.dart   # Secure credential storage
│   │
│   └── providers/
│       ├── repository_state_notifier.dart # Riverpod state + file watcher
│       └── providers.dart             # Riverpod provider exports
│
├── screens/
│   ├── home_page.dart                 # Repository list
│   ├── repository_page.dart           # Main Git view (changes, history, branches)
│   ├── commit_page.dart               # Commit details
│   └── settings_page.dart             # App settings
│
└── widgets/
    ├── repository_card.dart           # Repository list item
    ├── file_change_list.dart          # File changes widget
    ├── diff_viewer.dart               # Diff rendering widget
    ├── commit_history.dart            # Commit list
    └── branch_selector.dart           # Branch dropdown

```

## Data Flow

1. **User opens repository**:
   - UI calls `RepositoryService.openRepository(path)`
   - Service sends `OpenRepo` command to `GitIsolateManager`
   - Background isolate calls `git_repository_open()` via FFI
   - Returns `Repository` model to UI
   - `RepositoryStateNotifier` starts file watcher

2. **File watcher detects change**:
   - `Watcher` emits event
   - `RepositoryStateNotifier` starts 500ms debounce timer
   - Timer completes → triggers `git_status_foreach()` via isolate
   - Updates `RepositoryState` with modified files
   - UI rebuilds automatically (Riverpod)

3. **User views diff**:
   - UI requests diff for specific file
   - `DiffParser.parse()` executes on background isolate
   - Walks `git_diff` pointers, builds `List<DiffHunk>`
   - Returns to UI
   - `DiffViewer` widget renders with syntax highlighting

4. **User commits changes**:
   - UI collects commit message and staged files
   - `RepositoryService.commit()` sends to isolate
   - Background isolate calls `git_commit_create()` via FFI
   - Returns commit hash
   - `RepositoryStateNotifier` refreshes state

5. **User pushes to remote**:
   - `RepositoryService.push()` sends to isolate
   - `git_remote_push()` requires credentials
   - `libgit2` calls `CredentialsProvider` callback
   - Callback returns PAT from secure storage
   - Push completes, UI shows success

## UI Design Principles

- **No Material Design**: Custom widgets with sleek, modern aesthetic
- **Color Palette**: Dark grays, blues, and greens (GitHub-inspired)
- **Spacing**: Generous padding (16-32px) for breathing room
- **Typography**: Inter font family (clean, readable)
- **Layout**: 3-column design (repos, changes, diff viewer)
- **Animations**: Smooth transitions for all state changes

## Dependencies

Required packages (to be added):
- `riverpod` / `flutter_riverpod` - State management
- `ffi` - FFI bindings
- `watcher` - File system monitoring
- `flutter_secure_storage` - Secure credential storage
- `path` - Path manipulation
- `collection` - Utility collections

Native dependencies (bundled):
- `libgit2` (Windows: .dll, macOS: .dylib, Linux: .so)

## Security Considerations

- Personal Access Tokens stored in platform keychain (never in plaintext)
- SSH keys use system SSH agent
- No credentials logged or exposed in UI
- FFI pointers never escape isolate boundaries (prevents memory corruption)

## Performance Optimizations

- All Git operations on background isolate (no UI blocking)
- Debounced file watching (reduces redundant status checks)
- Lazy loading for commit history (virtualized list)
- Diff rendering uses virtualized scrolling for large files
- Repository list cached in local database (fast startup)

## Testing Strategy

- Unit tests for all services (mock FFI calls)
- Integration tests for isolate communication
- Widget tests for UI components
- Manual testing on all platforms (Windows, macOS, Linux)

## Future Enhancements

- Pull request management (GitHub/GitLab API)
- Merge conflict resolution UI
- Interactive rebase
- Stash management
- Submodule support
- Git LFS integration
