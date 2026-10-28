# T265 (TM2) support patch for librealsense v2.59.1

Restores support for the end-of-life Intel RealSense T265 tracking
camera to librealsense **v2.59.1** (upstream removed it in v2.54.1).

<img width="3759" height="2115" alt="image" src="https://github.com/user-attachments/assets/9bfa222c-de14-4f01-8adb-c51ed8c28f94" />


| File | What it is |
|---|---|
| `t265-port-v2.59.1.patch` | 29 source/build files (19 added, 10 modified); plain text; **no firmware, no prebuilt artifacts** |
| `install-t265-patch.sh` | verifies the target is byte-identical to v2.59.1 (git tree hash) and applies the patch |

## Where to apply it

In the original repository's (https://github.com/realsenseai/librealsense)
build process, the patch goes in **between obtaining the source and the
CMake configure step** — i.e. on the pristine v2.59.1 checkout, **before**
you build:

```
clone v2.59.1  →  APPLY PATCH HERE  →  configure/build as documented upstream
```

Concretely:

```sh
git clone --depth 1 -b v2.59.1 https://github.com/realsenseai/librealsense.git
cd librealsense
bash /path/to/install-t265-patch.sh --repo . --patch
```

(or simply `git apply t265-port-v2.59.1.patch`).

Everything after that — dependencies, configure options, build and
installation — is exactly as documented for the original repository
(see its `doc/` directory and the wiki page
"Build Configuration":
https://github.com/realsenseai/librealsense/wiki/Build-Configuration).
T265 support is on by default; `-DBUILD_WITH_TM2=OFF` at configure time
gives the standard build.

**Firmware:** not bundled with this patch. It is downloaded
automatically during the CMake configure step (from the public
conda-forge `librealsense-2.53.1` package, SHA1-verified) and cached in
`<repo-parent>/.fw-cache`, so rebuilds work offline. Prerequisites for
that download: `curl`, `unzip`, `zstd`, `nm`, `python3`; or pass a local
copy via `install-t265-patch.sh --fw <file>` / `T265_FW_CACHE`.

## Reverting

```sh
bash install-t265-patch.sh --repo /path/to/librealsense --unapply
```

(after a commit of the patch: `git reset --hard HEAD~1`)

## Provenance / license

Generated from the author's private `t265-port` fork of librealsense
(commit `5ab13f74e`, tag `v2.59.1+tm2.1`). Apache-2.0, as the
librealsense SDK.
