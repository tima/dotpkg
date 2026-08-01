# GitHub shorthand resolves to a single-bundle repo

When a user runs `dotpkg add tima/claude-code`, dotpkg clones `github.com/tima/claude-code` and expects `bundle.info` at the repo root — the repo IS the bundle. We considered an alternative where shorthand resolves a bundle name within a user's collection repo (parallel to how Sources work), but that requires dotpkg to know which collection to search, reintroducing the Sources lookup. The single-bundle-per-repo model is unambiguous: the repo name is the bundle name, one clone per bundle, no search required.

## Considered Options

- **Repo is the bundle** (chosen): `bundle.info` at root. One repo, one bundle. Simple resolution.
- **Repo contains bundles**: shorthand like `tima/claude-code` means "find bundle `claude-code` in a collection repo owned by `tima`" — but dotpkg would need to know which collection repo, which collapses back into Sources.
