#!/usr/bin/env bash
# RFC-0033 test mocks: an in-file ini editor standing in for kreadconfig6/
# kwriteconfig6 over the Plasma appletsrc, plus a recording plasma-apply stub.
# Sourced by tests/test_activation_wallpapers.sh. Never touches real config.

APPLETSRC="${XDG_CONFIG_HOME}/plasma-org.kde.plasma.desktop-appletsrc"
WP_APPLY_LOG="${HOME}/wp_apply.log"; : > "$WP_APPLY_LOG"

# Build the ini section header "[G1][G2]..." from repeated --group args.
_wpmock_section() { local s=""; local g; for g in "$@"; do s="${s}[${g}]"; done; printf '%s' "$s"; }

kreadconfig6() {
  local file="" default="" key=""; local -a groups=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --group) groups+=("$2"); shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --default) default="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local sec; sec="$(_wpmock_section "${groups[@]}")"
  local out
  out="$(awk -v sec="$sec" -v k="$key" '
    $0==sec {inS=1; next}
    /^\[/ {inS=0}
    inS && substr($0,1,length(k)+1)==k"=" { print "F" substr($0,length(k)+2); exit }
  ' "$file" 2>/dev/null || true)"
  if [ "${out:0:1}" = "F" ]; then printf '%s\n' "${out:1}"; else printf '%s\n' "$default"; fi
}

kwriteconfig6() {
  local file="" key="" delete=0 value="" have_value=0; local -a groups=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --group) groups+=("$2"); shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --delete) delete=1; shift 2 ;;   # our callers pass `--delete ""`
      --*) shift ;;
      *) value="$1"; have_value=1; shift ;;
    esac
  done
  local sec; sec="$(_wpmock_section "${groups[@]}")"
  [ -f "$file" ] || : > "$file"
  local tmp; tmp="$(mktemp)"
  awk -v sec="$sec" -v k="$key" -v val="$value" -v del="$delete" '
    $0==sec { inS=1; secseen=1; print; next }
    /^\[/ {
      if (inS && !done && !del) { print k"=" val; done=1 }
      inS=0; print; next
    }
    inS && substr($0,1,length(k)+1)==k"=" {
      if (del) { next } else { print k"=" val; done=1; next }
    }
    { print }
    END {
      if (inS && !done && !del) { print k"=" val; done=1 }
      if (!secseen && !del) { print sec; print k"=" val }
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$file"
}

# Recording stub — logs the applied path, never touches the real desktop.
plasma-apply-wallpaperimage() { printf '%s\n' "$1" >> "$WP_APPLY_LOG"; return 0; }

# Seed a single-desktop appletsrc: one folder desktop [1] on org.kde.image, plus a
# panel [2] that must be ignored. $1 = the current desktop image value (optional).
wp_seed_single() {
  local img="${1:-file:///usr/share/wallpapers/Next/contents/images/1.png}"
  {
    printf '[Containments][1]\n'
    printf 'plugin=org.kde.plasma.folder\n'
    printf 'wallpaperplugin=org.kde.image\n'
    printf '[Containments][1][Wallpaper][org.kde.image][General]\n'
    printf 'Image=%s\n' "$img"
    printf '[Containments][2]\n'
    printf 'plugin=org.kde.panel\n'
    printf 'wallpaperplugin=org.kde.image\n'
  } > "$APPLETSRC"
}

# Seed two folder desktops with distinct images ([1] and [3]), plus a panel [2].
wp_seed_dual() {
  local a="${1:-file:///a.png}" b="${2:-file:///b.png}"
  {
    printf '[Containments][1]\nplugin=org.kde.plasma.folder\nwallpaperplugin=org.kde.image\n'
    printf '[Containments][1][Wallpaper][org.kde.image][General]\nImage=%s\n' "$a"
    printf '[Containments][2]\nplugin=org.kde.panel\n'
    printf '[Containments][3]\nplugin=org.kde.plasma.folder\nwallpaperplugin=org.kde.image\n'
    printf '[Containments][3][Wallpaper][org.kde.image][General]\nImage=%s\n' "$b"
  } > "$APPLETSRC"
}

# Read the current image of a containment (test-side convenience over the mock).
wp_cur() { kreadconfig6 --file "$APPLETSRC" --group Containments --group "$1" --group Wallpaper --group org.kde.image --group General --key Image --default __NONE__; }
