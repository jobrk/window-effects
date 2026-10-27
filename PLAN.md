# Window Effects and desktop migration

Build a small macOS companion to AeroSpace for window shadows and opacity, then
make the complete desktop reproducible through the existing repository suite.
Window Effects owns appearance; AeroSpace owns tiling, workspaces and shortcuts.

## Repository responsibilities

| Repository | Owns |
|---|---|
| `~/projects/window-effects` | Source, tests, releases, installation interface and compatibility evidence |
| `~/projects/dotfiles` | AeroSpace bindings, Window Effects appearance policy, Stow selection and user documentation |
| `~/projects/ansible` | Package installation, pinned Window Effects build, macOS preferences and service lifecycle |

## Completed implementation

1. [x] Prove direct SkyLight access against an owned window and a separate process.
   Direct cross-process writes returned success but readback did not change.
   Own-process opacity works; no-shadow tags require Dock even for owned windows.
2. [x] Implement a narrow Dock payload and loader with attributed
   upstream code, keeping all window policy outside Dock.
3. [x] Add apply/restore/doctor/watch commands and installation instructions.
4. [x] Finish tests and perform a live Dock test (administrator-authenticated loading).
   Own backend changed and restored a separate process's shadow and alpha with
   yabai's daemon stopped. Arm64 and arm64e integration tests pass.
5. [x] Commit a usable release with explicit compatibility evidence and limits.

## Remaining migration work

6. [ ] Complete and commit the **dotfiles** profile.
   AeroSpace config, installer selection, smoke-test and CI changes are already
   prepared but uncommitted. Add a `window-effects` Stow package containing
   `.config/window-effects/config.json`, select it on macOS, and test both packages
   together. Keep Ghostty's decoration setting and existing machine-local values.
   Update the migration/rollback guide to include our appearance helper and remove
   stale statements that the combined setup cannot provide shadows/opacity.

7. [ ] Complete and commit **Ansible** provisioning.
   AeroSpace installation and explicit macOS preference tasks are already prepared
   but uncommitted. Add Window Effects installation pinned to an immutable commit
   or checksummed release artifact, with a retrievable source established before
   declaring fresh-machine provisioning complete. The project currently has no
   remote. Install root-owned backend files with `become`, user files without it,
   and stow the policy before enabling the watcher. Make service activation and
   hash-pinned autoload explicit choices; do not prompt for passwords from launchd.
   Preserve existing yabai/skhd packages and configuration through the trial.

8. [ ] Validate the **three repositories together**.
   Run Window Effects tests, Stow smoke tests, Ansible lint/syntax/check mode and
   a targeted provisioning run followed by an idempotence run. Exercise a fresh
   temporary home as well as migration of existing config. Confirm provisioning
   does not run conflicting window managers or overwrite local settings. Document
   Accessibility authorization and the SIP/arm64e prerequisites as manual steps.
   Preserve unrelated local edits, including the existing Neovim, zsh and yabai
   changes, and commit only this migration's changes in each repository.

9. [ ] Perform the **live cutover on macOS 26.6.2**.
   Stop yabai/skhd and restart Dock to remove the old resident scripting addition.
   Load only our backend, repeat the live appearance test, then activate AeroSpace
   and the watcher using the versioned configuration. Test Ghostty, Zen and Spotify,
   focus, dialogs, exclusions, workspaces, resizing, sleep/wake, monitor changes,
   independent AeroSpace/Dock restarts, and restoration/rollback.

10. [ ] Verify **macOS 27** on the actual target build.
    Repeat the acceptance checks in COMPATIBILITY.md and record OS build, tested
    Window Effects revision and the matching Ansible/dotfiles revisions. Compilation
    and tests on macOS 26 do not establish macOS 27 compatibility.

11. [ ] Retire the old setup after acceptance.
    Remove obsolete yabai/skhd services, packages, scripting-addition files and
    their dedicated sudoers entry. Update provisioning and docs to match the final
    state. Retain an identifiable rollback revision across all three repositories.
    Our backend still requires Dock injection; do not re-enable SIP while it needs
    the existing reduced configuration.

The implementation release is complete; the repository-suite migration and live
acceptance milestones above remain open. COMPATIBILITY.md records the actual
runtime evidence and limitations.

Current machine: macOS 26.6.2 (25G83), Apple Silicon. macOS 27 cannot be
runtime-validated here. Never mark it tested from an OS version check alone.

Keep the running desktop intact unless a short, reversible test is necessary.
Do not change SIP or install passwordless sudo rules automatically.
