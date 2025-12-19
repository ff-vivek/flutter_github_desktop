# GitDesktop: Full Feature Roadmap (Flutter + libgit2 via dart:ffi)

This roadmap targets near-parity with GitHub Desktop while respecting our isolate-based FFI architecture and go_router navigation already present in the repo.

Principles
- All libgit2 calls run on a background isolate (GitIsolateManager).
- UI remains responsive; command/response pattern with typed payloads.
- Pure Dart models cross the isolate boundary only (no pointers on UI side).
- Riverpod for state; debounced file watching to avoid status thrashing.
- DynamicLibraryService loads libgit2 per-platform.

Milestones and Epics

0) Bootstrap & Foundation
- App shell, theming, go_router routes (done)
- GitIsolateManager command bus with SendPort/ReceivePort (done)
- CredentialsProvider scaffolding with NativeCallable and exceptionalReturn (done)
- DynamicLibraryService for platform DLL loading (done)

1) Repository Management (MVP onboarding)
- Open existing repository (path input for now; later platform pickers)
- Show repo header: branch, head, dirty/clean status
- List changes: modified, staged, untracked (mock until FFI wired)
- Quick actions: Stage/Unstage, Commit, Refresh (mock wired)

2) Clone/Create/Add Flows
- Clone via URL + destination path (PAT/SSH credentials hook)
- Create new repository in folder (git_repository_init)
- Add existing repository (folder picker)
- Persist recent repositories (secure storage/JSON; web-safe fallback)

3) Commit Workflow
- Staging area with file tree, checkbox interactions
- Diff viewer per-file with syntax tinted code and inline stats
- Commit message composer with validation; amend last commit
- Undo last commit (soft reset), discard changes for file/hunk/line

4) Branching & History
- Branch list: create/rename/delete/switch, upstream tracking
- Graph view of commit history; search, author/date filters
- Compare branches/commits; checkout file from commit

5) Remote Operations
- Remote list & tracking branches; set upstream
- Fetch/Pull/Push with progress, credentials callback
- Rebase: start/continue/abort; merge with conflict UI

6) Diff Engine & Review
- libgit2 diff traversal on isolate; map to DiffHunk/DiffLine
- Rich diff UI: additions/deletions, hunks navigation, word-diff toggle
- Binary/large file handling; partial staging by hunk/line

7) Advanced: Stash, Submodules, LFS, Hooks
- Stash create/pop/list; apply with index
- Submodule status/update/init
- LFS detection messaging (no upload in-app initially)
- Client-side hooks opt-in (pre-commit run + results)

8) Performance, Caching, Robustness
- LRU caches for status/diff per file; invalidated via watcher
- Batched filesystem events with 500ms debounce (done in notifier)
- Error types and user-friendly messages; retry flows
- Telemetry toggled off by default

9) UX Polish
- Keyboard shortcuts and focus management
- Animations for panel transitions and list updates
- Theming refinements; high-contrast mode

Security & Credentials
- PAT/SSH via CredentialsProvider; later secure storage integration
- Never log secrets; redact URLs

Non-Goals (v1)
- GitHub issues/PRs UI
- Git LFS file upload flows

Implementation Item 1 (Repository Management / MVP onboarding) — DONE ✅
- “Open Repository” flow on Home implemented:
  - Path input field (desktop-friendly for now)
  - On open: GitIsolateManager.OpenRepoCommand + GetStatusCommand (mock)
  - Displays repo header (branch/head/dirty) and lists of changes
  - Actions: Refresh (wired), Commit/Stage/Unstage (mock stubs)

Implementation Item 2 (Clone/Create/Add Flows) — DONE ✅
- Clone/Create/Add flows wired with bottom sheets on Home
  - Clone via URL + destination path (mock isolate command)
  - Create new repository in folder (mock init command)
  - Add existing repository (path validation via OpenRepo mock)
  - Persist recent repositories (shared_preferences; web-safe)

Current Implementation Item 3 — IN PROGRESS 🚧
- Commit workflow UI with message composer
- Stage/Unstage interactions in file lists (mock local state)
- Diff viewer using DiffParser mock (up next)

Next Items (after 3):
4. Branch list + simple history list (mock rev-walk)
5. Remote operations skeleton (push/fetch with credentials hook)
