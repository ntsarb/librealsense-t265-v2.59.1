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
  --fw <file>        local T265 firmware file (target.mvcmd), seeded into the
                     build's FW cache
  --fw-source <src>  T265 firmware source: URL (http/https/file) or local path;
                     exported as T265_FW_SOURCE for the configure-time fetch
  --allow-dirty      proceed despite tracked local modifications
  --yes              do not prompt (the firmware must then come from --fw,
                     --fw-source, T265_FW_SOURCE, or a valid T265_FW_CACHE)
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
FW_SOURCE=""
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
        --fw-source)   FW_SOURCE="${2:?--fw-source needs a value}"; shift 2 ;;
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
git -C "$REPO" apply --reverse --check --whitespace=nowarn "$PATCH" 2>/dev/null && patch_applied=1

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
    git -C "$REPO" apply --reverse --whitespace=nowarn "$PATCH"
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
    # --whitespace=nowarn: the ported TM2 sources carry pre-existing trailing
    # whitespace; the patch is faithful to them, so silence the cosmetic warning
    git -C "$REPO" apply --whitespace=nowarn "$PATCH" \
        || die "git apply failed" 1
    git -C "$REPO" apply --reverse --check --whitespace=nowarn "$PATCH" \
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

    # Firmware resolution. The T265 firmware is a proprietary Intel/RealSense
    # binary; scripts/fetch-t265-fw.sh has no default download source, so it
    # must come from the cache, an explicit source (local file or URL), or an
    # interactive prompt.
    if [ -n "$FW" ]; then
        [ -f "$FW" ] || die "--fw file not found: $FW" 2
        if ! echo "$FW_SHA1  $FW" | sha1sum -c --status 2>/dev/null; then
            die "firmware SHA1 mismatch: $FW (expected $FW_SHA1)" 2
        fi
        mkdir -p "$BUILD_DIR/fw-cache"
        cp "$FW" "$BUILD_DIR/fw-cache/target.mvcmd"
        say "firmware seeded into $BUILD_DIR/fw-cache/target.mvcmd"
        export T265_FW_CACHE="$BUILD_DIR/fw-cache"
    fi
    if [ -n "$FW_SOURCE" ]; then
        export T265_FW_SOURCE="$FW_SOURCE"
        say "firmware source (from --fw-source): $FW_SOURCE"
    fi

    fw_available=0
    cache_dir="${T265_FW_CACHE:-}"
    if [ -n "$cache_dir" ] \
        && echo "$FW_SHA1  $cache_dir/target.mvcmd" | sha1sum -c --status 2>/dev/null; then
        fw_available=1
        say "firmware: cache hit in $cache_dir/target.mvcmd"
    fi
    if [ "$fw_available" -eq 0 ] && [ -n "${T265_FW_SOURCE:-}" ]; then
        fw_available=1
        say "firmware source (from environment): $T265_FW_SOURCE"
    fi
    if [ "$fw_available" -eq 0 ]; then
        if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
            die "no T265 firmware available (proprietary binary; there is no default download source).
Provide it with one of:
  --fw <file>            local firmware file (target.mvcmd, v0.2.0.951)
  --fw-source <src>      URL (http/https/file) or local path to the firmware
  T265_FW_SOURCE=<src>   URL or local path, in the environment
  T265_FW_CACHE=<dir>    cache directory already containing a verified target.mvcmd
expected SHA1: $FW_SHA1" 2
        fi
        printf 'T265 firmware v0.2.0.951 is not cached and no source is set\n'
        printf '(proprietary binary; there is no default download source).\n'
        printf 'Enter a URL (http/https/file) or a local file path: '
        read -r ans
        [ -n "$ans" ] || die "firmware source required; aborted" 2
        export T265_FW_SOURCE="$ans"
        say "firmware source: $ans (SHA1-verified at configure time)"
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
