# Remote bundle trust: preview required for GitHub shorthand, not for Sources

GitHub shorthand bundles (`dotpkg add user/repo`) show a gum-formatted preview of all bundle files — `bundle.info`, `Brewfile`, `defaults.sh`, `extensions.txt`, `requires.txt` — and require explicit `y` confirmation before any action is taken. Sources-listed repos (`~/.dotpkg/sources`) skip this preview.

The distinction is where the trust decision happens. Adding a repo to `~/.dotpkg/sources` is itself a deliberate, auditable trust act — the user has already reviewed and opted in. GitHub shorthand is one-off and lower-trust: the user may be installing a bundle they've never seen before. Showing the full bundle contents before execution makes the risk visible without adding a blanket gate to every install.

We do not attempt to lint or sandbox `defaults.sh` — shell parsing is unreliable and creates false confidence. The preview is the gate; what users do after confirming is their responsibility.
