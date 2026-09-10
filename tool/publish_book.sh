#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: bash tool/publish_book.sh RENDERED_DIRECTORY REPOSITORY_URL' >&2
  exit 64
fi

rendered_directory=$(cd "$1" && pwd)
repository_url=$2
if ! test -f "$rendered_directory/index.html" || ! rg -qi 'name="generator" content="quarto' "$rendered_directory/index.html"; then
  echo 'Expected rendered Quarto HTML with index.html. Render the book first.' >&2
  exit 1
fi

publish_directory=$(mktemp -d "${TMPDIR:-/tmp}/quarto-pages.XXXXXX")
trap 'rm -rf "$publish_directory"' EXIT

# Work in a temporary checkout; the source checkout and branch stay untouched.
git init --quiet --initial-branch=gh-pages "$publish_directory"
git -C "$publish_directory" remote add origin "$repository_url"
if git -C "$publish_directory" ls-remote --exit-code --heads origin gh-pages >/dev/null; then
  git -C "$publish_directory" fetch --quiet --depth=1 origin gh-pages
  git -C "$publish_directory" reset --quiet --hard FETCH_HEAD
fi
rsync -a --delete --exclude='.git' "$rendered_directory/" "$publish_directory/"
touch "$publish_directory/.nojekyll"
git -C "$publish_directory" add --all
if git -C "$publish_directory" diff --cached --quiet; then
  echo 'Published content is already up to date.'
  exit 0
fi
git -C "$publish_directory" commit --quiet -m 'Publish rendered Quarto book'
# A concurrent publication is rejected normally; never overwrite remote history.
git -C "$publish_directory" push origin gh-pages:refs/heads/gh-pages
