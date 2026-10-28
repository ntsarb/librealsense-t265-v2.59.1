#!/usr/bin/env bash
# License: Apache 2.0. See LICENSE file in root directory.
# Copyright(c) 2026 RealSense, Inc. All Rights Reserved.
#
# Turn a fresh stock clone of upstream librealsense v2.59.1 into a
# T265-capable source tree by applying packaging/t265-port-v2.59.1.patch.
#
# The base is verified by git tree hash (the pristine v2.59.1 tree), so the
# installer refuses anything that is not byte-identical to v2.59.1.
#
# Default action: apply the patch and stop (no commit, no build).
#
# Usage:
#   git clone --depth 1 -b v2.59.1 https://github.com/realsenseai/librealsense.git
#   cd librealsense
#   install-t265-patch.sh --patch            # patch and stop
#   install-t265-patch.sh --build            # patch + build lib + tool
#   install-t265-patch.sh --unapply          # back to pristine v2.59.1
#
# Exit codes: 0 ok, 1 apply/build failure, 2 base/precondition failure,
#             3 unapply precondition (patch not applied)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DEFAULT="$SCRIPT_DIR/t265-port-v2.59.1.patch"
BASE_TREE="7ab58c5e35de9fa96b310c0cb798ef0cd94cb364"   # pristine v2.59.1 tree
EXPECTED_FILES=29
FW_SHA1="c3940ccbb0e3045603e4aceaa2d73427f96e24bc"

die() { echo "error: $*" >&2; exit "${2:-1}"; }
say() { echo "$*" >&2; }

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --repo <dir>       v2.59.1 clone to patch (default: current directory)
  --patch            apply the patch (skipped if already applied) [default]
  --commit           also commit the applied changes
  --build            configure + build realsense2 + rs-enumerate-devices
  --unapply          reverse-apply the patch (restore pristine v2.59.1)
  --build-dir <d>    build directory (default: <repo>/build)
  --fw <file>        T265 firmware file, seeded into the build's FW cache
  --allow-dirty      proceed despite tracked local modifications
  --yes              do not prompt
  --help             this help
EOF
}

REPO="."
PATCH="$PATCH_DEFAULT"
DO_PATCH=1
DO_COMMIT=0
DO_BUILD=0
DO_UNAPPLY=0
BUILD_DIR=""
FW=""
ALLOW_DIRTY=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)        REPO="${2:?--repo needs a value}"; shift 2 ;;
        --patch)       DO_PATCH=1; shift ;;
        --commit)      DO_COMMIT=1; shift ;;
        --build)       DO_BUILD=1; shift ;;
        --unapply)     DO_UNAPPLY=1; DO_PATCH=0; shift ;;
        --build-dir)   BUILD_DIR="${2:?--build-dir needs a value}"; shift 2 ;;
        --fw)          FW="${2:?--fw needs a value}"; shift 2 ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        --yes)         ASSUME_YES=1; shift ;;
        --help|-h)     usage; exit 0 ;;
        *)             die "unknown option: $1 (see --help)" 2 ;;
    esac
done

# --- locate repo ------------------------------------------------------------
[ -d "$REPO" ] || die "repo directory not found: $REPO" 2
REPO="$(cd "$REPO" && pwd)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$REPO is not a git repository" 2

# --- patch integrity ----------------------------------------------------------
[ -f "$PATCH" ] || die "patch not found: $PATCH" 2
if grep -q '^GIT binary patch' "$PATCH"; then
    die "patch contains binary sections (unexpected)" 2
fi
patch_files="$(grep -c '^diff --git' "$PATCH")"
[ "$patch_files" -eq "$EXPECTED_FILES" ] \
    || die "patch has ${patch_files} files, expected ${EXPECTED_FILES} (corrupt or wrong version)" 2

# --- base check: pristine v2.59.1 ---------------------------------------------
head_tree="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
if [ "$head_tree" != "$BASE_TREE" ]; then
    if [ "$DO_UNAPPLY" -eq 1 ]; then
        # not at the base: only meaningful if the patch content is present
        git -C "$REPO" apply --reverse --check "$PATCH" 2>/dev/null \
            || die "base tree mismatch and the patch is not applied in $REPO (nothing to unapply)" 2
    elif [ -e "$REPO/src/tm2/tm-device.cpp" ]; then
        die "T265 support appears to be already present in $REPO (nothing to do; use --unapply to revert)" 2
    else
        die "base tree mismatch:
  expected pristine v2.59.1 (tree $BASE_TREE)
  got                  $head_tree
Clone a fresh base with:
  git clone --depth 1 -b v2.59.1 https://github.com/realsenseai/librealsense.git" 2
    fi
fi

# --- patch state + dirtiness -------------------------------------------------
patch_applied=0
git -C "$REPO" apply --reverse --check "$PATCH" 2>/dev/null && patch_applied=1

tracked_changes="$(git -C "$REPO" status --porcelain --untracked-files=no)"
if [ -n "$tracked_changes" ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
    if [ "$patch_applied" -eq 1 ]; then
        say "note: uncommitted tracked changes are the applied patch; continuing"
    else
        die "tracked local modifications present; commit/stash them or pass --allow-dirty:
$tracked_changes" 2
    fi
fi
untracked_count="$(git -C "$REPO" status --porcelain --untracked-files=all | grep -c '^??' || true)"
if [ "$untracked_count" -gt 0 ]; then
    say "note: $untracked_count untracked file(s) in $REPO (ignored)"
fi

# --- unapply -------------------------------------------------------------------
if [ "$DO_UNAPPLY" -eq 1 ]; then
    if ! git -C "$REPO" apply --reverse --check "$PATCH" 2>/dev/null; then
        die "patch is not currently applied in $REPO (nothing to unapply)" 3
    fi
    if [ "$(git -C "$REPO" rev-parse 'HEAD^{tree}')" != "$BASE_TREE" ]; then
        die "the patch is committed at HEAD in $REPO; to revert:
  git -C $REPO reset --hard HEAD~1" 1
    fi
    say "reverse-applying patch in $REPO ..."
    git -C "$REPO" apply --reverse "$PATCH"
    # a failed earlier --commit may leave the patch staged; the worktree is
    # now back at the base content, so unstaging loses nothing
    git -C "$REPO" reset --quiet
    remaining="$(git -C "$REPO" status --porcelain --untracked-files=no)"
    [ -z "$remaining" ] || die "unapply left tracked modifications behind;
restore manually with: git -C $REPO reset --hard
$remaining" 1
    say "done: $REPO is back to pristine v2.59.1"
    exit 0
fi

# --- apply --------------------------------------------------------------------
if [ "$DO_PATCH" -eq 1 ] && [ "$patch_applied" -eq 0 ]; then
    say "applying T265 port patch (${patch_files} files) to: $REPO"
    git -C "$REPO" apply --stat "$PATCH"
    if [ "$ASSUME_YES" -eq 0 ]; then
        printf "Proceed? [y/N] "
        read -r ans
        [ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "aborted by user"
    fi
    git -C "$REPO" apply "$PATCH" \
        || die "git apply failed" 1
    git -C "$REPO" apply --reverse --check "$PATCH" \
        || die "patch did not apply completely" 1
    say "applied: $(git -C "$REPO" diff --shortstat | sed 's/^ *//') (+ new files)"
    say "working tree is now v2.59.1 + T265 port (uncommitted)"
elif [ "$DO_PATCH" -eq 1 ]; then
    say "patch already applied; nothing to apply"
fi

# --- commit -------------------------------------------------------------------
if [ "$DO_COMMIT" -eq 1 ]; then
    if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
        say "nothing to commit (patch already committed, or no changes)"
    else
        git -C "$REPO" config user.email >/dev/null \
            || die "git user.email is not set in $REPO; run e.g.
  git config user.name  'Your Name'
  git config user.email 'you@example.com'
and re-run with --commit" 2
        git -C "$REPO" add -A
        git -C "$REPO" commit -m "Apply T265 port on top of v2.59.1 (t265-port-v2.59.1.patch)"
        say "committed: $(git -C "$REPO" rev-parse --short HEAD)"
    fi
fi

# --- build --------------------------------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    [ -n "$BUILD_DIR" ] || BUILD_DIR="$REPO/build"

    fw_cache="${T265_FW_CACHE:-}"
    if [ -n "$FW" ]; then
        [ -f "$FW" ] || die "--fw file not found: $FW" 2
        if ! echo "$FW_SHA1  $FW" | sha1sum -c --status 2>/dev/null; then
            die "firmware SHA1 mismatch: $FW (expected $FW_SHA1)" 2
        fi
        fw_cache="$BUILD_DIR/fw-cache"
        mkdir -p "$fw_cache"
        cp "$FW" "$fw_cache/target.mvcmd"
        say "firmware seeded into $fw_cache/target.mvcmd"
        export T265_FW_CACHE="$fw_cache"
    fi
    if [ -n "$fw_cache" ]; then
        say "T265_FW_CACHE=$fw_cache"
    else
        say "firmware: scripts/fetch-t265-fw.sh will resolve the cache (download if missing)"
    fi

    say "configuring in $BUILD_DIR ..."
    cmake -S "$REPO" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release \
        || die "cmake configure failed" 1

    say "building realsense2 + rs-enumerate-devices ..."
    cmake --build "$BUILD_DIR" --target realsense2 rs-enumerate-devices -j"$(nproc)" \
        || die "build failed" 1

    bin="$BUILD_DIR/Release/rs-enumerate-devices"
    [ -x "$bin" ] || die "rs-enumerate-devices not found at $bin" 1
    say "smoke test: running $bin ..."
    smoke_rc=0
    smoke_out="$(timeout 20 "$bin" 2>&1)" || smoke_rc=$?
    case "$smoke_out" in
        *"error while loading shared libraries"*|*"undefined symbol"*)
            echo "$smoke_out" >&2
            die "rs-enumerate-devices failed to load its library" 1 ;;
    esac
    if [ "$smoke_rc" -eq 124 ]; then
        die "rs-enumerate-devices timed out (20 s)" 1
    elif [ "$smoke_rc" -ge 128 ]; then
        echo "$smoke_out" >&2
        die "rs-enumerate-devices crashed (exit $smoke_rc)" 1
    elif [ "$smoke_rc" -ne 0 ]; then
        say "smoke test: exit $smoke_rc (device present but unavailable in this"
        say "environment, e.g. USB interface busy) -- not a build failure"
    fi
    say "done: library at $BUILD_DIR/Release/librealsense2.so.2.59.1"
fi

say "OK"
