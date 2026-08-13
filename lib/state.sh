#!/usr/bin/env bash
# ponytail: python3 for JSON (ships with Xcode CLT, sys.argv avoids injection)

STATE_FILE="${STATE_FILE:-$DOTPKG_HOME/state.json}"

state_init() {
  [[ -s "$STATE_FILE" ]] && return
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"
}

state_bundle_installed() {
  local name="$1"
  python3 - "$name" "$STATE_FILE" <<'EOF'
import json, sys
name, f = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
sys.exit(0 if any(b["name"] == name for b in s["installed_bundles"]) else 1)
EOF
}

state_add_bundle() {
  local name="$1" source="$2" stow_paths="${3:-}"
  python3 - "$name" "$source" "$stow_paths" "$STATE_FILE" <<'EOF'
import json, sys, datetime
name, src, stow_paths_str, f = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
stow_paths = stow_paths_str.split() if stow_paths_str else []
with open(f) as fh: s = json.load(fh)
if not any(b["name"] == name for b in s["installed_bundles"]):
    s["installed_bundles"].append({
        "name": name, "source": src,
        "installed_at": datetime.date.today().isoformat(),
        "stow_paths": stow_paths
    })
with open(f, "w") as fh: json.dump(s, fh, indent=2)
EOF
}

state_add_preset() {
  local name="$1"
  python3 - "$name" "$STATE_FILE" <<'EOF'
import json, sys
name, f = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
if name not in s.get("installed_presets", []):
    s.setdefault("installed_presets", []).append(name)
with open(f, "w") as fh: json.dump(s, fh, indent=2)
EOF
}

state_remove_bundle() {
  local name="$1"
  python3 - "$name" "$STATE_FILE" <<'EOF'
import json, sys
name, f = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
s["installed_bundles"] = [b for b in s["installed_bundles"] if b["name"] != name]
with open(f, "w") as fh: json.dump(s, fh, indent=2)
EOF
}

state_list_bundles() {
  python3 - "$STATE_FILE" <<'EOF'
import json, sys
with open(sys.argv[1]) as fh: s = json.load(fh)
for b in s["installed_bundles"]: print(b["name"])
EOF
}

state_get_bundle_source() {
  local name="$1"
  python3 - "$name" "$STATE_FILE" <<'EOF'
import json, sys
name, f = sys.argv[1], sys.argv[2]
with open(f) as fh: s = json.load(fh)
for b in s["installed_bundles"]:
    if b["name"] == name:
        print(b.get("source", "local"))
        sys.exit(0)
sys.exit(1)
EOF
}

state_get_json() {
  cat "$STATE_FILE"
}
