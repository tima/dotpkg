# Adversarial Review — dotpkg Bundle Installation
**Reports under review:** code-intel-external-run1.md, code-intel-local-run1.md  
**Source files verified:** dotpkg (root), lib/bundle.sh, lib/stow.sh, lib/state.sh  
**Reviewer:** Claude Sonnet 4.6 | 2026-08-05

---

## Verdict by Claim

### 1. Does `dotpkg install` exist?

Both correct. The dispatch case at dotpkg:422-436 lists `init`, `add`, `sync`, `status`, `list`, `update`, `create`, `adopt`, `help`, `--version/-v`. No `install` case. Both reports name `dotpkg add` as the install entry point. No errors.

### 2. Step order in install_bundle()

Both correct. Actual order in lib/bundle.sh:168-255:

```
Validation (bundle.info exists, name non-empty, visited-set) -> requires.txt deps -> Brewfile -> stow/ -> defaults.sh -> extensions.txt -> themes/ -> state_add_bundle
```

Neither report omits a step or inverts the order.

### 3. Line numbers — external report

Most line numbers are accurate; six are wrong:

| Claim | Cited | Actual | Notes |
|-------|-------|--------|-------|
| conflicts grep in stow_check | stow.sh:8 | stow.sh:7 | line 8 is the `if` guard, not the grep |
| extensions.txt guard | bundle.sh:237 | bundle.sh:236 | |
| "not found" warning branch | bundle.sh:157-159 | bundle.sh:156-158 | |
| other error branch | bundle.sh:160-162 | bundle.sh:159-162 | |
| themes/ guard | bundle.sh:243 | bundle.sh:242 | |
| resolve_bundle call for dep | bundle.sh:198 | bundle.sh:197 | line 198 is the error-handling block |

All errors are off-by-one; none invert a claim.

**Additional error in external Strengths & Weaknesses section:**  
"greps stderr for conflict strings" — wrong. lib/stow.sh:6 captures combined stdout+stderr via `2>&1` before grepping. The actual output variable holds merged output. The step description earlier in the same report says "Greps output" (correct), making the S&W section internally inconsistent.

**Executive summary count error:**  
Claims "9 steps." The code has 7 listed operations after validation (deps, Brewfile, stow, defaults, extensions, themes, state). If stow_check and stow_apply count separately that's 8. No combination produces 9 consistently.

### 4. Brewfile — source guard

Both correct. lib/bundle.sh:206-209 has no source guard — Brewfile runs regardless of `$source`. The external report says "No conditional on source" (correct). The local report is silent on this (also correct). No conflict between reports.

### 5. stow_check dry-run flag

Both correct. lib/stow.sh:6: `stow --dir="$bundle_dir" --target="$target" -n -v stow 2>&1`. Both reports cite `-n -v`.

### 6. defaults.sh condition

Both correct. lib/bundle.sh:226: `if [[ "$source" == "local" ]];` — exact match for both reports' claims.

### 7. extensions.txt — editor list

Both correct. lib/bundle.sh:139: `for _ed in code cursor codium;` — matches both reports exactly.

### 8. themes/ skip condition

Both correct. Two guards: `[[ -d "$bundle_dir/themes" ]]` at line 242 and `[[ -n "$theme_target" ]]` at line 245. Both reports identify this correctly.

### 9. state_add_bundle mechanism

Both correct. lib/state.sh:22-37 uses embedded Python3 (`python3 - "$name" "$source" "$stow_paths" "$STATE_FILE" <<'EOF'`) to read/write `~/.dotpkg/state.json`. Deduplication guard: `if not any(b["name"] == name ...)`.

### 10. Visited-set data structure

Local report: explicitly correct — "colon-delimited string." lib/bundle.sh:8: `[[ ":${_DOTPKG_VISITED}:" == *":${1}:"* ]]`, lib/bundle.sh:12: `_DOTPKG_VISITED="${_DOTPKG_VISITED:+${_DOTPKG_VISITED}:}${1}"`.

External report: calls it a "visited-set" but doesn't describe the data structure. Not wrong, but incomplete.

### 11. Steps neither report mentions

None missing. All eight operations in install_bundle() are covered.

---

## Errors in Local Report

One error: local report line 17 says "Library files sourced at startup (line 14): all `~/.dotpkg/lib/*.sh`." Actual dotpkg:14: `for _lib in "$DOTPKG_HOME/lib"/*.sh; do`. The path uses `$DOTPKG_HOME`, which defaults to `~/.dotpkg` but is user-overridable via env var. The hardcoded `~/.dotpkg` is the common case but not the authoritative statement. Very minor.

---

## Which Report Is More Accurate

**Local report wins.** It has one trivial path-hardcoding inaccuracy. External has six off-by-one line number errors, one internal inconsistency (stow stderr vs combined output), and an incorrect step count in the executive summary. Both capture the architecture and logic correctly; the external report's granular line citations are a double-edged sword — they're mostly right but wrong just often enough to undermine trust in the fine detail.

Local report's edge: correctly identifies the visited-set as a colon-delimited string. Correctly attributes stow abort to `set -e` propagation. Correctly flags the `state_add_bundle` deduplication-vs-source-change gap.

---

## ast-grep Usage

Neither report mentions `sg` or ast-grep in any methodology or tool description. Both appear to have used file reads and plain-text search only.

---

## New Verification Gaps (beyond prior Additions 1-4, Gaps A-K)

**Gap L — cmd_sync source blindness**  
`cmd_sync` calls `install_bundle "$bundle_dir" "local"` for every bundle regardless of how it was originally installed (dotpkg:113-120). Bundles installed via GitHub shorthand (source="github") had their defaults.sh skipped. On sync, they get source="local" and defaults.sh executes. Neither report calls this out. This is a security-relevant behavior change: a GitHub bundle's defaults.sh, reviewed and skipped at install time, silently runs on the next `dotpkg sync`.

**Gap M — stow_check swallows stow process failure**  
lib/stow.sh:6 appends `|| true` after the stow command: `output=$(stow ... 2>&1) || true`. If stow is not installed or crashes, the exit code is discarded, `$output` may be empty or a shell error message, `$conflicts` will be empty, and stow_check returns 0 — a false "no conflicts" signal. Neither report covers this.

**Gap N — stow_paths whitespace join**  
lib/bundle.sh:221: `find ... | tr '\n' ' '` produces a space-joined string passed to state_add_bundle. Python splits on whitespace: `stow_paths_str.split()`. A stow package directory with a space in its name would corrupt the stow_paths record. Neither report covers this, though it's low-probability in practice.

**Gap O — _DOTPKG_VISITED shared across root + profile in cmd_init**  
`cmd_init` resets `_DOTPKG_VISITED=""` before the root bundle install (dotpkg:54) but does NOT reset it before the profile install (dotpkg:66). Both root and profile share the same visited-set, preventing shared dependencies from being double-installed during init. This is correct behavior but undocumented in either report. Neither report notes the asymmetry with cmd_add (which resets at line 81, covering only the full add flow).

---

## Run-Time Comparison

| | External | Local |
|--|---------|-------|
| Wall-clock | 144s | 126s |
| Tool calls | 16 | 18 |
| Line-number errors | 6 | 0 |
| Logic errors | 1 (stow stderr claim) | 0 |
| Missing structural detail | visited-set type | none found |

Local was faster with more tool calls, suggesting it was more targeted. External's extra time produced more granular citations at the cost of more off-by-one errors.

---

Reviewed by: Claude Sonnet 4.6 | 2026-08-05
