#!/usr/bin/env bash
set -euo pipefail

# Release script for John Maven
# Usage: bash scripts/release.sh <major|minor|patch|x.y.z>
# Examples:
#   bash scripts/release.sh patch   # 1.0.1 -> 1.0.2
#   bash scripts/release.sh minor   # 1.0.1 -> 1.1.0
#   bash scripts/release.sh major   # 1.0.1 -> 2.0.0
#   bash scripts/release.sh 2.1.0   # explicit version

CURRENT_VERSION=$(node -p "require('./package.json').version")

if [[ -z "${1:-}" ]]; then
  echo "Usage: bash scripts/release.sh <major|minor|patch|x.y.z>"
  echo "Current version: ${CURRENT_VERSION}"
  exit 1
fi

# Parse current version
IFS='.' read -r CUR_MAJOR CUR_MINOR CUR_PATCH <<< "$CURRENT_VERSION"

case "$1" in
  major) VERSION="$((CUR_MAJOR + 1)).0.0" ;;
  minor) VERSION="${CUR_MAJOR}.$((CUR_MINOR + 1)).0" ;;
  patch) VERSION="${CUR_MAJOR}.${CUR_MINOR}.$((CUR_PATCH + 1))" ;;
  *)     VERSION="$1" ;;
esac
TAG="v${VERSION}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_ROOT"

# Ensure gh CLI is available
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is required. Install it: https://cli.github.com"
  exit 1
fi

# Ensure working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is dirty. Commit or stash changes first."
  exit 1
fi

# Find the previous tag (most recent), or use root commit if none exist
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -z "$PREV_TAG" ]]; then
  RANGE="HEAD"
else
  RANGE="${PREV_TAG}..HEAD"
fi

echo "Releasing ${TAG}"
echo "Commits: ${RANGE}"
echo ""

# Collect commits and categorize into Changes and Fixes
CHANGES=""
FIXES=""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Extract subject (everything after the short hash + space)
  subject="${line#* }"
  if echo "$subject" | grep -qi "^fix"; then
    FIXES="${FIXES}- ${subject}\n"
  else
    CHANGES="${CHANGES}- ${subject}\n"
  fi
done < <(git log --oneline --no-merges "$RANGE" | grep -v "^.*Bump version$")

# Build release body
BODY=""
if [[ -n "$CHANGES" ]]; then
  BODY+="### Changes\n\n${CHANGES}\n"
fi
if [[ -n "$FIXES" ]]; then
  BODY+="### Fixes\n\n${FIXES}\n"
fi

if [[ -z "$BODY" ]]; then
  echo "Error: no commits found for release notes."
  exit 1
fi

# Preview
echo "--- Release notes ---"
echo -e "$BODY"
echo "---------------------"
echo ""

# Prompt for confirmation
read -rp "Create release ${TAG}? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# Bump version in package.json
if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
  # Use node for a reliable in-place JSON edit
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    pkg.version = '${VERSION}';
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  "
  git add package.json
  git commit -m "Bump version to ${VERSION}"
fi

# Create tag
git tag "$TAG"

# Push tag
git push origin "$TAG"

# Create GitHub release
echo -e "$BODY" | gh release create "$TAG" \
  --title "John Maven ${VERSION}" \
  --notes-file -

echo ""
echo "Released ${TAG}: https://github.com/DelphiOneGit/D1_JohnMaven/releases/tag/${TAG}"
