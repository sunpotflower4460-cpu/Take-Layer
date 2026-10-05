#!/usr/bin/env bash
# Core boundary + TimelineMapper authority guard. Needs only bash/grep/sed/awk
# (Linux and macOS). Usage: tools/check-core-boundary.sh [REPO_ROOT]
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 2
LIST="tools/core-files.txt"
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

strip_comments() { sed -E 's#//.*$##' "$1"; }

[ -f "$LIST" ] || { echo "missing $LIST"; exit 2; }
CORE=()
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
  [ -n "$line" ] && CORE+=("$line")
done < "$LIST"
echo "Core files: ${#CORE[@]}"

# 1. existence, import allowlist, forbidden tokens
FORBIDDEN='UIKit|SwiftUI|AVFoundation|AVKit|AppKit|UIImage|UIColor|UIFont|UIScreen|QuartzCore|CoreAnimation|CALayer|CATextLayer'
ALLOWED_MODULES=" Foundation CryptoKit "
for f in "${CORE[@]}"; do
  [ -f "$f" ] || { fail "$f listed but missing"; continue; }
  while IFS= read -r imp; do
    mod="$(echo "$imp" | sed -E 's/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|func|var|let|typealias)[[:space:]]+)?([A-Za-z0-9_]+).*/\4/')"
    case "$ALLOWED_MODULES" in *" $mod "*) ;; *) fail "$f imports disallowed module '$mod'";; esac
  done < <(strip_comments "$f" | grep -E '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]')
  hits="$(strip_comments "$f" | grep -nwE "$FORBIDDEN" || true)"
  [ -n "$hits" ] && fail "$f mentions forbidden token(s): $(echo "$hits" | head -3 | tr '\n' ' ')"
done

# 2. direction check: Core must not reference types declared in non-Core files
DECL_RE='^[[:space:]]*((public|private|fileprivate|internal|final)[[:space:]]+)*(struct|enum|class|protocol|typealias|actor)[[:space:]]+[A-Z][A-Za-z0-9_]*'
NONCORE_TYPES="$(mktemp)"; trap 'rm -f "$NONCORE_TYPES"' EXIT
while IFS= read -r g; do
  skip=0; for c in "${CORE[@]}"; do [ "$g" = "$c" ] && skip=1; done
  [ $skip = 1 ] && continue
  strip_comments "$g" | grep -oE "$DECL_RE" | awk '{print $NF}'
done < <(find TakeLayer tools -name '*.swift' | sort) | sort -u > "$NONCORE_TYPES"
for f in "${CORE[@]}"; do
  [ -f "$f" ] || continue
  # remove types the Core file set declares itself (name clash safety)
  strip_comments "$f" | sed -E 's/"[^"]*"//g' | grep -oE '\b[A-Z][A-Za-z0-9_]*\b' | sort -u |
  while IFS= read -r t; do
    if grep -qx "$t" "$NONCORE_TYPES"; then
      owner="$(grep -rlE "(struct|enum|class|protocol|typealias|actor)[[:space:]]+$t\b" TakeLayer tools --include=*.swift | head -1)"
      echo "FAIL: $f references non-Core type '$t' (declared in $owner)"
    fi
  done
done > /tmp/.core-dir.$$ 2>&1
if [ -s /tmp/.core-dir.$$ ]; then cat /tmp/.core-dir.$$; FAIL=1; fi
rm -f /tmp/.core-dir.$$

# 3. Package.swift sources must equal core-files.txt (minus TakeLayer/ prefix)
if [ -f Package.swift ]; then
  want="$(printf '%s\n' "${CORE[@]}" | sed 's#^TakeLayer/##' | sort)"
  have="$(awk '/name: "TakeLayerCore",/{f=1} f{print} f&&/^            \]/{exit}' Package.swift | grep -oE '"[A-Za-z0-9_/]+\.swift"' | tr -d '"' | sort)"
  [ "$want" = "$have" ] || fail "Package.swift sources differ from $LIST"
fi

# 3b. Rendering layer (above Core): no UIKit/SwiftUI/AppKit
RLIST="tools/rendering-files.txt"
if [ -f "$RLIST" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"; [ -z "$line" ] && continue
    [ -f "$line" ] || { fail "$line listed in $RLIST but missing"; continue; }
    hits="$(strip_comments "$line" | grep -nwE 'UIKit|SwiftUI|AppKit|UIColor|UIImage|UIFont|UIScreen' || true)"
    [ -n "$hits" ] && fail "$line (rendering layer) mentions UI token(s): $(echo "$hits" | head -3 | tr '\n' ' ')"
  done < "$RLIST"
fi

# 4. TimelineMapper authority guard (heuristic, line-based; see docs)
FAMILY='songStartRawSec|songStartAudioSec|offsetMs|projectTimelineSec|videoRawSec|masterAudioSec|audioSourceStartSec|audioInsertionTimeSec'
while IFS= read -r g; do
  case "$g" in */Services/TimelineMapper.swift) continue;; esac
  strip_comments "$g" | grep -nE . | while IFS= read -r numbered; do
    n="${numbered%%:*}"; l="${numbered#*:}"
    # G1: ms -> s conversion of an offset
    if echo "$l" | grep -qE 'offsetMs|[Oo]ffset[A-Za-z]*Ms' && echo "$l" | grep -qE '/[[:space:]]*\(?1_?000|0\.001'; then
      echo "FAIL: $g:$n offset ms->s arithmetic outside TimelineMapper: $l"
    fi
    # G2: spaced binary +/- mixing >=2 distinct sync-family identifiers
    k="$(echo "$l" | grep -oE "\b($FAMILY)\b" | sort -u | wc -l)"
    if [ "$k" -ge 2 ] && echo "$l" | grep -qE '[A-Za-z0-9_)\]][[:space:]]+[-+][[:space:]]+[A-Za-z0-9_(]'; then
      echo "FAIL: $g:$n sync-time arithmetic outside TimelineMapper: $l"
    fi
    # G3: re-declaring mapper API names
    if echo "$l" | grep -qE 'func[[:space:]]+(projectTimelineSec|videoRawSec|masterAudioSec|remapProjectTimelineSec|makeMapping)\b'; then
      echo "FAIL: $g:$n redeclares TimelineMapper API: $l"
    fi
  done
done < <(find TakeLayer tools -name '*.swift' | sort) > /tmp/.core-auth.$$ 2>&1
if [ -s /tmp/.core-auth.$$ ]; then cat /tmp/.core-auth.$$; FAIL=1; fi
rm -f /tmp/.core-auth.$$

if [ $FAIL = 0 ]; then echo "OK: core boundary and TimelineMapper authority checks passed"; else exit 1; fi
