#!/usr/bin/env bash
# Debuggable, fail-fast release generator that assumes CWD is the target repo.
# Creates all commits & tags locally, pushes ONCE at the end, then creates releases.
set -Eeuo pipefail

# ---- Optional full trace -----------------------------------------------------
# Enable with: TRACE=1 ./make-releases.sh
if [[ "${TRACE:-0}" == "1" ]]; then
  export PS4='+ [${BASH_SOURCE##*/}:${LINENO}] '
  set -x
fi

# ---- Pretty logging helpers --------------------------------------------------
ts() { date +"%Y-%m-%d %H:%M:%S%z"; }
log() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ❌ $*" >&2; exit 1; }
section() { echo; echo "[$(ts)] ===== $* ====="; }

trap 'die "Command failed at ${BASH_SOURCE[0]}:${LINENO}: ${BASH_COMMAND}"' ERR

# ---- Required config ---------------------------------------------------------
: "${GH_TOKEN:?Need GH_TOKEN (GitHub token with repo scope)}"
: "${OWNER:?Need OWNER (GitHub username or org)}"
: "${REPO:?Need REPO (repository name)}"

API="https://api.github.com"
REMOTE_EXPECTED="github.com/${OWNER}/${REPO}"

# CLEAN_MODE: abort|stash|wipe
CLEAN_MODE="${CLEAN_MODE:-abort}"

# ---- Preflight checks --------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
need git; need curl; need jq; need go

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository."

REMOTE_URL="$(git config --get remote.origin.url || true)"
log "Detected origin remote: ${REMOTE_URL:-<none>}"
[[ "$REMOTE_URL" == *"$REMOTE_EXPECTED"* ]] || die "Origin remote does not match expected $REMOTE_EXPECTED"

section "Verifying GitHub token"
AUTH_USER_JSON="$(curl -sS -H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json" "$API/user")" || true
AUTH_LOGIN="$(jq -r '.login // empty' <<<"$AUTH_USER_JSON")"
[[ -n "$AUTH_LOGIN" && "$AUTH_LOGIN" != "null" ]] || { echo "$AUTH_USER_JSON"; die "Could not validate GH_TOKEN with GitHub API."; }
log "Authenticated as: $AUTH_LOGIN"

section "Checking repository access"
REPO_JSON="$(curl -sS -H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json" "$API/repos/${OWNER}/${REPO}")" || true
REPO_FULL_NAME="$(jq -r '.full_name // empty' <<<"$REPO_JSON")"
[[ "$REPO_FULL_NAME" == "${OWNER}/${REPO}" ]] || { echo "$REPO_JSON"; die "Cannot access ${OWNER}/${REPO}. Check OWNER/REPO and token permissions."; }
log "Repo OK: $REPO_FULL_NAME"

# ---- Preparing working tree (with modes) -------------------------------------
section "Preparing working tree (mode: ${CLEAN_MODE})"

is_dirty=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  is_dirty=1
fi

if [[ "$is_dirty" -eq 1 ]]; then
  case "$CLEAN_MODE" in
    abort) die "Working tree is not clean. Set CLEAN_MODE=stash or CLEAN_MODE=wipe, or commit/stash manually." ;;
    stash)
      log "Stashing uncommitted changes (including untracked)…"
      STASH_REF="$(git stash push -u -m "pre-releases backup $(date -u +%Y%m%dT%H%M%SZ)" | tail -n1 | sed 's/.*\(stash@{[0-9]\+}\).*/\1/;t;d' || true)"
      [[ -n "$STASH_REF" ]] || STASH_REF="(unknown; see git stash list)"
      log "Stashed as: ${STASH_REF}"
      ;;
    wipe)
      log "Hard resetting and cleaning working tree (DESTRUCTIVE)…"
      git reset --hard
      git clean -fdx
      ;;
    *) die "Unknown CLEAN_MODE: $CLEAN_MODE (use abort|stash|wipe)" ;;
  esac
else
  log "Working tree is clean."
fi

# Ensure repo has at least one commit (helps pushes when repo was empty)
if [ -z "$(git rev-list --max-count=1 HEAD 2>/dev/null || true)" ]; then
  log "No commits yet; creating baseline empty commit."
  git commit --allow-empty -m "chore: baseline"
fi

# ---- Reset project contents to a blank slate ---------------------------------
section "Resetting project contents to a blank slate"
git rm -rf . >/dev/null 2>&1 || true
find . -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} + 2>/dev/null || true
git add -A
git commit -m "chore: prepare empty baseline" >/dev/null 2>&1 || true

# ---- Create project files ----------------------------------------------------
section "Creating project files"
cat > main.go <<'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello")
}
EOF

cat > tools.go <<'EOF'
//go:build tools
// +build tools

package tools

import (
	_ "golang.org/x/text/language"
	_ "github.com/gorilla/websocket"
	_ "golang.org/x/net/html"
	_ "golang.org/x/crypto/ssh"
	_ "github.com/gin-gonic/gin"
	_ "github.com/golang-jwt/jwt/v4"
)
EOF

cat > README.md <<'EOF'
# go-vuln-releases

This repo is auto-generated for testing vulnerability scanners across 10 releases.
A full changelog and vulnerability matrix will be written at the end of the script run.
EOF

# Initialize module if needed
if [[ -f go.mod ]]; then
  log "go.mod already exists; leaving module path as-is."
else
  MODULE="example.com/${REPO}"
  log "Initializing go module: ${MODULE}"
  go mod init "${MODULE}"
fi

# ---- Helpers -----------------------------------------------------------------
gh_post() {
  local path="$1"; shift
  local json="$1"; shift

  log "GitHub POST ${path}"
  log "Payload (truncated): $(echo "$json" | tr -d '\n' | head -c 220)$( [ "$(echo "$json" | wc -c)" -gt 220 ] && echo "…")"

  local tmp_body; tmp_body="$(mktemp)"
  local http_code
  http_code="$(curl -sS -o "$tmp_body" -w "%{http_code}" \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -X POST "${API}${path}" -d "${json}")" || true

  log "GitHub API status: ${http_code}"
  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "---- GitHub API error body ----"
    cat "$tmp_body"
    echo "-------------------------------"
    rm -f "$tmp_body"
    die "GitHub API request failed (${http_code}) for ${path}"
  fi
  rm -f "$tmp_body"
}

show_pins() {
  log "Currently pinned versions:"
  go list -m all 2>/dev/null | grep -E '(^golang.org/x/text$|^github.com/gorilla/websocket$|^golang.org/x/net$|^golang.org/x/crypto$|^github.com/gin-gonic/gin$|^github.com/golang-jwt/jwt/v4$)' || true
}

# Force-pin modules by editing go.mod directly (avoids go get solver conflicts)
force_pin() {
  # Usage: force_pin module@ver [module@ver ...]
  if [ "$#" -eq 0 ]; then
    log "force_pin: nothing to pin"
    return 0
  fi

  for pair in "$@"; do
    mod="${pair%@*}"
    ver="${pair#*@}"
    log "Pinning: require ${mod} ${ver}"
    go mod edit -require="${mod}@${ver}"

    # Drop existing replace for this module (if any), then replace to the exact version
    if go mod edit -json | jq -e --arg m "$mod" '.Replace[]? | select(.Old.Path==$m)' >/dev/null; then
      log "Dropping existing replace for ${mod}"
      go mod edit -dropreplace="${mod}" || true
    fi
    log "Adding replace: ${mod} => ${mod} ${ver}"
    go mod edit -replace="${mod}=${mod}@${ver}"
  done

  log "Downloading modules (best-effort)…"
  go mod download all 2>&1 | sed 's/^/[download] /' || true

  log "Tidying with -e (continue on errors) and tools tag…"
  go mod tidy -e -tags tools 2>&1 | sed 's/^/[tidy] /' || true

  show_pins
}

# Store releases to create later (after a single push)
RELEASE_TAGS=()
RELEASE_TITLES=()

queue_release() {
  local tag="$1"; shift
  local title="$1"; shift
  RELEASE_TAGS+=("$tag")
  RELEASE_TITLES+=("$title")
}

# Commit + tag locally (no push here)
tag_release() {
  local tag="$1"; shift
  local title="$1"; shift

  log "Ensuring clean working tree before committing…"
  git add -A
  git commit -m "$title" || true
  local head_commit
  head_commit="$(git rev-parse --short HEAD)"
  log "Committed $head_commit for $title"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    die "Tag ${tag} already exists locally. Aborting to avoid conflicts."
  fi

  log "Tagging ${tag}"
  git tag "${tag}"

  queue_release "$tag" "$title"
}

# ---- Release sequence (local commits & tags only) ----------------------------
section "Release R1 (v0.1.0) — vulnerable baseline"
force_pin \
  golang.org/x/text@v0.3.6 \
  github.com/gorilla/websocket@v1.4.0 \
  golang.org/x/net@v0.37.0 \
  golang.org/x/crypto@v0.34.0 \
  github.com/gin-gonic/gin@v1.8.1 \
  github.com/golang-jwt/jwt/v4@v4.5.2
tag_release "v0.1.0" "R1: initial vulnerable dependencies"

section "Release R2 (v0.2.0) — change x/text"
force_pin golang.org/x/text@v0.3.5
tag_release "v0.2.0" "R2: change x/text within vulnerable range"

section "Release R3 (v0.3.0) — change gin"
force_pin github.com/gin-gonic/gin@v1.6.3
tag_release "v0.3.0" "R3: change gin to another vulnerable version"

section "Release R4 (v0.4.0) — change x/net"
force_pin golang.org/x/net@v0.36.0
tag_release "v0.4.0" "R4: change x/net within vulnerable range"

section "Release R5 (v0.5.0) — change x/crypto"
force_pin golang.org/x/crypto@v0.33.0
tag_release "v0.5.0" "R5: change x/crypto within vulnerable range"

section "Release R6 (v0.6.0) — fix to clean versions"
force_pin \
  golang.org/x/text@v0.3.8 \
  github.com/gorilla/websocket@v1.5.3 \
  golang.org/x/net@v0.38.0 \
  golang.org/x/crypto@v0.35.0 \
  github.com/gin-gonic/gin@v1.9.1
tag_release "v0.6.0" "R6: upgrade to fixed versions"

section "Release R7 (v0.7.0) — safe bump x/net"
force_pin golang.org/x/net@v0.39.0
tag_release "v0.7.0" "R7: safe bump of x/net"

section "Release R8 (v0.8.0) — reintroduce vuln via jwt/v4"
force_pin github.com/golang-jwt/jwt/v4@v4.5.1
tag_release "v0.8.0" "R8: downgrade jwt/v4 to vulnerable version"

section "Release R9 (v0.9.0) — fix jwt/v4"
force_pin github.com/golang-jwt/jwt/v4@v4.5.2
tag_release "v0.9.0" "R9: fix jwt/v4"

section "Release R10 (v1.0.0) — safe bump x/crypto"
force_pin golang.org/x/crypto@v0.36.0
tag_release "v1.0.0" "R10: safe bump of x/crypto"

# ---- Final README with matrix & changelog (after tags, before single push) ---
section "Writing final README.md"
cat > README.md <<'EOF'
# go-vuln-releases

This Go repository is designed for **testing vulnerability scanners**.  
It has **10 releases** (v0.1.0–v1.0.0) where only dependencies change between versions.  
Releases **R1–R5** and **R8** include modules with known CVEs in their `go.mod`.

---

## 🔄 Changelog

| Tag | Summary |
|-----|----------|
| **v1.0.0 (R10)** | Safe bump of `x/crypto` to v0.36.0 – ✅ Clean |
| **v0.9.0 (R9)** | Fix `jwt/v4` to v4.5.2 – ✅ Clean |
| **v0.8.0 (R8)** | Downgrade `jwt/v4` to v4.5.1 – ❌ Vulnerable (CVE-2025-30204) |
| **v0.7.0 (R7)** | Safe bump `x/net` to v0.39.0 – ✅ Clean |
| **v0.6.0 (R6)** | Upgrade to fixed dependency versions – ✅ Clean |
| **v0.5.0 (R5)** | Change `x/crypto` to v0.33.0 – ❌ Vulnerable |
| **v0.4.0 (R4)** | Change `x/net` to v0.36.0 – ❌ Vulnerable |
| **v0.3.0 (R3)** | Change `gin` to v1.6.3 – ❌ Vulnerable |
| **v0.2.0 (R2)** | Change `x/text` to v0.3.5 – ❌ Vulnerable |
| **v0.1.0 (R1)** | Initial vulnerable baseline – ❌ Vulnerable |

---

## 🧩 Vulnerability Matrix

| Release | x/text | gorilla/websocket | x/net | x/crypto | gin | golang-jwt/jwt/v4 |
|----------|--------|-------------------|--------|-----------|-----|-------------------|
| **v1.0.0 (R10)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.36.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.9.0 (R9)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.8.0 (R8)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ❌ v4.5.1 (CVE-2025-30204) |
| **v0.7.0 (R7)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.39.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.6.0 (R6)** | ✅ v0.3.8 | ✅ v1.5.3 | ✅ v0.38.0 | ✅ v0.35.0 | ✅ v1.9.1 | ✅ v4.5.2 |
| **v0.5.0 (R5)** | ❌ v0.3.5 (CVE-2021-38561) | ❌ v1.4.0 (CVE-2020-27813) | ❌ v0.36.0 (CVE-2025-22872) | ❌ v0.33.0 (CVE-2025-22869) | ❌ v1.6.3 (CVE-2023-26125) | ✅ v4.5.2 |
| **v0.4.0 (R4)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.36.0 | ❌ v0.34.0 | ❌ v1.6.3 | ✅ v4.5.2 |
| **v0.3.0 (R3)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.6.3 | ✅ v4.5.2 |
| **v0.2.0 (R2)** | ❌ v0.3.5 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.8.1 | ✅ v4.5.2 |
| **v0.1.0 (R1)** | ❌ v0.3.6 | ❌ v1.4.0 | ❌ v0.37.0 | ❌ v0.34.0 | ❌ v1.8.1 | ✅ v4.5.2 |

### CVE References
- `golang.org/x/text` — CVE-2021-38561 (fixed in ≥ v0.3.7)  
- `github.com/gorilla/websocket` — CVE-2020-27813 (fixed in ≥ v1.4.1)  
- `golang.org/x/net` — CVE-2025-22872 (fixed in ≥ v0.38.0)  
- `golang.org/x/crypto` — CVE-2025-22869 (fixed in ≥ v0.35.0)  
- `github.com/gin-gonic/gin` — CVE-2023-26125 (fixed in ≥ v1.9.0)  
- `github.com/golang-jwt/jwt/v4` — CVE-2025-30204 (fixed in ≥ v4.5.2)
EOF

git add README.md
git commit -m "docs: add changelog and vulnerability matrix" || true

# ---- SINGLE PUSH (branch + all tags) ----------------------------------------
section "Pushing branch & ALL tags (single push)"
git push -u origin HEAD --tags

# ---- Create GitHub releases AFTER tags are on remote -------------------------
section "Creating GitHub releases"
for i in "${!RELEASE_TAGS[@]}"; do
  tag="${RELEASE_TAGS[$i]}"
  title="${RELEASE_TITLES[$i]}"
  log "Creating release for ${tag} – ${title}"
  gh_post "/repos/${OWNER}/${REPO}/releases" "$(jq -n \
    --arg tag "$tag" \
    --arg name "$title" \
    --arg body "$title" \
    '{tag_name:$tag, name:$name, body:$body, draft:false, prerelease:false}')"
done

section "All done!"
log "Releases page: https://github.com/${OWNER}/${REPO}/releases"

if [[ "${CLEAN_MODE}" == "stash" && -n "${STASH_REF:-}" ]]; then
  echo
  log "Your previous work is stashed as: ${STASH_REF}"
  log "List stashes with: git stash list"
  log "Inspect with:      git stash show -p ${STASH_REF}"
fi

