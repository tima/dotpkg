# Adversarial Review: Bundle Source Resolution Reports (Run 2)

**Reports reviewed:**
- External: `code-intel-external-run2.md` (218s, 26 tool calls)
- Local: `code-intel-local-run2.md` (143s, 22 tool calls)

**Verified against:** `dotpkg` (436 lines), `lib/bundle.sh` (255 lines), `lib/state.sh` (73 lines)

---

## Primary Contradiction: cmd_sync Behavior

**The code (dotpkg lines 105-124):**

```bash
cmd_sync() {
  state_init
  _DOTPKG_VISITED=""
  echo "Syncing installed bundles..."

  local names bundle_dir
  names=$(state_list_bundles)

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if bundle_dir=$(resolve_bundle "$name" 2>/dev/null); then
      install_bundle "$bundle_dir" "local"
    else
      echo "  skipping missing bundle: $name" >&2
    fi
  done <<< "$names"
  ...
}
```

**`state_list_bundles` (lib/state.sh:62-68):**

```python
for b in s["installed_bundles"]: print(b["name"])
```

Only `name` is emitted. The stored `source` field is never read. `state.json` does store `source` (set by `state_add_bundle`), but `cmd_sync` does not query it.

**Verdict: External is correct, Local is misleading.**

External's primary claim — "GitHub bundles silently skip during sync" — is accurate for the typical case. A GitHub bundle (`user/repo`) has its declared `name=` field from `bundle.info` stored in state (e.g., `"my-bundle"`). `cmd_sync` calls `resolve_bundle "my-bundle"`. Since `"my-bundle"` contains no `/`, it never reaches Tier 4 (`*/*` check at lib/bundle.sh:80). Resolution fails. `cmd_sync` prints "skipping missing bundle" to stderr (suppressed by `2>/dev/null` inside the loop — the redirection is on `resolve_bundle`, not on the `echo`). The GitHub cache at `~/.dotpkg/cache/github/user/repo` is unreachable.

Local's primary claim — "defaults.sh EXECUTES on sync (security bypass)" — is technically possible but describes only an edge case: a GitHub bundle whose declared name coincidentally matches a local bundle or registered source. In that case, `resolve_bundle` would find that local path (not the GitHub cache), call `install_bundle` with hardcoded `"local"`, and `defaults.sh` would execute. This is a real latent design flaw but not the typical runtime behavior. The local report's Strengths/Weaknesses table states this as the primary weakness without qualification, implying it's the normal behavior. That framing is wrong.

Both reports acknowledge the hardcoded `"local"` label and the declared-name resolution problem — the difference is which they lead with. External leads with the skip (more accurate for the common case). Local leads with the execute (more accurate only in an edge case, presented without that qualification in the weakness table).

---

## Verification: Other Claims

### 1. Number of resolution tiers

- External: "5-step resolution sequence (steps 0-4)" — CORRECT
- Local: Executive summary says "four tiers" — WRONG. Body lists Tiers 0, 1, 2, 3, 4 (five tiers, 0-indexed), contradicting its own summary.

Actual code comments in lib/bundle.sh:
```
# 0. Root bundle
# 1. Local bundle
# 2. Profile
# 3. Sources
# 4. GitHub shorthand (user/repo)
```

Five steps. Local's "four tiers" in the executive summary is an internal contradiction.

### 2. resolve_bundle line range

- External: "lib/bundle.sh:44-91" — CORRECT. Function opens at line 44, closing `}` at line 91.
- Local: "lib/bundle.sh:44" — gives only the start line, incomplete.

### 3. _fetch_github_bundle: preview and confirmation

Both reports correctly describe the clone -> preview -> `_gum_confirm` sequence. Confirmed at lib/bundle.sh:94-133.

### 4. _clone_source: no confirmation

Both correctly note `_clone_source` (lib/bundle.sh:29-41) clones directly with no preview or confirmation. Confirmed.

### 5. Source label for source-repo bundles

Both correctly note source-repo bundle names never contain `/`, so `cmd_add` assigns `bundle_source="local"` (dotpkg:97). Confirmed.

### 6. state.json fields stored per bundle

`state_add_bundle` (lib/state.sh:22-37) stores: `name`, `source`, `installed_at`, `stow_paths`. State does capture the original source — the bug is that `state_list_bundles` discards it, and `cmd_sync` never queries it. Neither report fully articulates this: the fix would be to emit (or re-read) the source from state in `cmd_sync` and pass it to `install_bundle`.

### 7. Temp dir trap on RETURN

External: "trap fires on RETURN, deletes $tmp_dir" — CORRECT.
Local: "Temp dir is cleaned by a trap 'rm -rf $tmp_dir' RETURN" — CORRECT.

Actual code (lib/bundle.sh:102):
```bash
trap "rm -rf '$tmp_dir'" RETURN
```

Both correct. Trap is RETURN (function exit), not EXIT (shell exit).

### 8. ast-grep usage

- External: No mention of ast-grep. Used rg/grep without noting the fallback.
- Local: Explicitly noted "ast-grep (sg) does not support sh as a language and exited with error. All structural searches used rg/grep as the documented fallback."

Verified: `sg --lang sh` exits with `error: invalid value 'sh' for '--lang <LANG>': sh is not supported!` Local correctly documented the fallback. External silently used rg without acknowledging the preferred-tool guidance.

---

## Overall Verdict

**External is more accurate.** Its primary sync claim (skip, not execute) matches the actual control flow for the common case. Its step count (5) and line range (44-91) are both correct.

**Local has two factual errors:**
1. "Four tiers" in the executive summary contradicts the five tiers it lists in the body.
2. "defaults.sh EXECUTES on sync" as the primary weakness framing is misleading — it's only true in the edge case where a GitHub bundle's declared name shadows a local bundle name. The typical case is a silent skip, as external states.

Both reports correctly identify the hardcoded `"local"` label in `cmd_sync` and the declared-name storage bug. Neither report identifies the clean fix: `state_list_bundles` could emit `name source` pairs, and `cmd_sync` could pass the original source to `install_bundle`.

---

## New Gaps (beyond prior Gaps A-O / Additions 1-4)

**Gap P — state_add_bundle is append-only (no upsert).** If a bundle is already in state, `state_add_bundle` silently skips the write (`if not any(b["name"] == name ...): append`). This means re-sync never updates `source` in state.json even if it were passed correctly. Fixing the sync source label bug also requires changing `state_add_bundle` to upsert, not just append.

**Gap Q — `cmd_update` then `cmd_sync` is the real attack surface.** `cmd_update` pulls the GitHub cache dirs via `git pull`, then calls `cmd_sync`. If a GitHub bundle's declared name also exists as a local bundle (even by collision), `cmd_sync` post-update would execute the updated `defaults.sh` from the local bundle with `source="local"`. Neither report frames this as the complete threat path.

**Gap R — `state_bundle_installed` uses name only.** `state_bundle_installed` (lib/state.sh:12-19) checks membership by `name` alone. Two bundles from different sources with the same declared name are indistinguishable in state; the second silently deduplicates against the first. Neither report notes this collision risk.

---

## Run Metrics

| | External | Local |
|---|---|---|
| Time | 218s | 143s |
| Tool calls | 26 | 22 |
| ast-grep used | No (silent) | No (documented fallback) |
| Primary sync claim | Correct (skip) | Misleading (execute) |
| Tier count | Correct (5) | Wrong in summary (4), correct in body (5) |
| Line range | Correct (44-91) | Incomplete (44 only) |

Local is faster and cheaper, but External is more factually reliable on the primary contradiction tested here.
