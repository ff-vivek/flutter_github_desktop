 # Phase 3: Remotes + Auth (Fetch/Pull/Push)

 Goal: Sync with origin reliably with proper credential handling and progress feedback.

 ## Scope
 - Remotes management (list, add, remove, set-url)
 - Network operations (fetch, push)
 - Credentials provider & callbacks (SSH + HTTPS)
 - Progress reporting (side-channel messages for UI updates)
 - Error mapping and resilience (clear messages, retry guidance)

## Deliverables
1) Strengthen bindings foundation
   - [x] Add git_error_last mapping and throw helpers
   - [x] Bindings for remotes/network (partial):
     • git_remote_list, git_remote_lookup, git_remote_free, git_remote_url ✅
     • git_strarray + dispose ✅
     • git_remote_fetch ✅
     • git_remote_push ✅
     • git_remote_connect/check ✅
    - [x] Callback structs for progress and credentials ✅

2) Credentials provider
   - [x] Dart-side provider for HTTPS (username/password, PAT) and SSH (agent, key files)
   - [ ] Register via git_remote_set_callbacks (blocked by 1: callback structs)
   - [x] Cache per-host decisions for session

3) Remotes management commands
   - [x] GetRemotes (names + URLs) — implemented via isolate with libgit2 ✅
   - [x] AddRemote(name, url)
   - [x] RemoveRemote(name)
   - [x] SetRemoteUrl(name, url)

4) Fetch/Pull/Push flows
   - [x] Fetch with progress, auto-create tracking branches
   - [x] Push with forced/non-forced option, progress summary, set upstream post-push
   - [x] Basic pull (fast-forward only for now); rebase/merge later

5) UI integration
   - [x] Remotes panel (list, primary indicator, overflow actions)
   - [x] Pull/Fetch/Push buttons with non-blocking progress toasts
   - [x] Credentials prompt sheets when needed

6) Robust error handling
   - [x] Map negative rc to human messages using git_error_last
   - [x] Include remote/host info and suggestion (e.g., login or PAT)

## Milestones
- [x] M1: Remote list (names + URLs) via FFI + isolate command — DONE ✅
 - [x] M2: Set URL/Add/Remove remotes
- [x] M3: Fetch with progress + credentials skeleton (progress logs only for now)
  - [x] Basic fetch via git_remote_fetch (default refspecs, no callbacks)
- [x] M4: Push with progress + basic errors
- [x] M5: Pull (fast-forward only)

## Next pick
- Next: Credentials provider & prompts
  Rationale: enable HTTPS/SSH auth and richer progress callbacks.