#!/usr/bin/env bash
# test-gitlab-ci-raw-url.sh — issue #11.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
SANDBOX="${GITLAB_SANDBOX:-BankNatchapol/supersaiyan-gitlab-sandbox}"
FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Groups I–J (CI detect, raw URL)"
bash -n "$GITLAB_SH" || tfail "syntax"
# shellcheck disable=SC1090
. "$GITLAB_SH"

TD=$(mktemp -d)
# fixture: deploy job on main
mkdir -p "$TD/direct"
cat > "$TD/direct/.gitlab-ci.yml" <<'YML'
deploy:
  environment:
    name: production
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
  script: echo deploy
YML
platform_detect_production_ci "$TD/direct" || tfail "direct .gitlab-ci.yml deploy job not detected"

# fixture: include one local file
mkdir -p "$TD/inc/ci"
cat > "$TD/inc/.gitlab-ci.yml" <<'YML'
include:
  - local: ci/deploy.yml
test:
  script: echo hi
YML
cat > "$TD/inc/ci/deploy.yml" <<'YML'
deploy_prod:
  environment:
    name: production
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
  script: echo deploy
YML
platform_detect_production_ci "$TD/inc" || tfail "local include: deploy job not detected"

mkdir -p "$TD/none"
echo "test:\n  script: echo" > "$TD/none/.gitlab-ci.yml"
platform_detect_production_ci "$TD/none" && tfail "non-deploy CI was treated as production"

# raw URL uses config host
CFG="$TD/cfg.json"
cat > "$CFG" <<'EOF'
{"git_platform":"gitlab","project":{"host":"gitlab.example.com","full_path":"g/p"}}
EOF
export PLATFORM_CONFIG_PATH="$CFG"
url=$(platform_raw_file_url g/p main docs/shot.png)
[ "$url" = "https://gitlab.example.com/g/p/-/raw/main/docs/shot.png" ] \
  || tfail "raw url=$url"
echo "$url" | grep -q 'gitlab.com' && tfail "raw URL hardcoded gitlab.com despite config host"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if command -v glab >/dev/null && glab auth status >/dev/null 2>&1; then
  LIVE="$TD/live.json"
  cat > "$LIVE" <<EOF
{"git_platform":"gitlab","project":{"host":"gitlab.com","full_path":"$SANDBOX"}}
EOF
  export PLATFORM_CONFIG_PATH="$LIVE"
  # Protect main if not already
  glab api --method POST "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')/protected_branches" \
    -f name=main -F push_access_level=40 -F merge_access_level=40 >/dev/null 2>&1 || true
  if ! platform_detect_branch_protection main; then
    tfail "protected main was not detected"
  fi
  live_url=$(platform_raw_file_url "$SANDBOX" main README.md)
  echo "$live_url" | grep -q '/-/raw/main/README.md' || tfail "live raw url $live_url"
  # embed in issue #1 comment
  glab api --method POST "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')/issues/1/notes" \
    -f "body=raw embed: ${live_url}" >/dev/null || tfail "could not post raw URL embed"
  unset PLATFORM_CONFIG_PATH
else
  echo "  skip live protection/embed (glab not authenticated)"
fi

rm -rf "$TD"
[ "$FAIL" -eq 0 ] || { echo "error: gitlab CI/raw-url check failed" >&2; exit 1; }
echo "  ✓ Groups I–J: CI include detect, protection, host-based raw URL"
echo "PASS: test-gitlab-ci-raw-url.sh"
