# Bundle Sources

Bundles are resolved in this order:

1. **Local** — `~/dotfiles/bundles/<name>/`
2. **Profiles** — `~/dotfiles/profiles/<name>/`
3. **User remotes** — git repos in `~/.dotpkg/sources` (trusted, no preview)
4. **GitHub shorthand** — `user/repo` fetched from GitHub (full preview + confirmation required)

## User remotes

Add a line to `~/.dotpkg/sources`:

```
tima/dotpkg-bundles
myorg/shared-bundles
git@github.internal:team/bundles.git
```

Pull updates:

```bash
dotpkg update
```

## GitHub shorthand

Install a bundle directly from a GitHub repo (the repo root must be the bundle):

```bash
dotpkg add someuser/nord-bundle
```

dotpkg shows a full preview of bundle.info, Brewfile, defaults.sh, extensions.txt, and requires.txt before asking for confirmation. Nothing is installed without explicit `y`.
