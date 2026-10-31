# Unofficial T265 (TM2) support patch for librealsense v2.59.1

Restores support for the end-of-life Intel RealSense T265 tracking
camera to librealsense **v2.59.1** (upstream removed it in v2.54.1).

<img alt="image" src="https://github.com/user-attachments/assets/22c22dee-f08c-4738-8fe9-ab8433c87feb" />


| File | What it is |
|---|---|
| `t265-port-v2.59.1.patch` | 29 source/build files (19 added, 10 modified); plain text; **no firmware, no prebuilt artifacts** |
| `install-t265-patch.sh` | verifies the target is byte-identical to v2.59.1 (git tree hash) and applies the patch |

## Where to apply it

In the original repository's (https://github.com/realsenseai/librealsense)
build process (https://github.com/realsenseai/librealsense/blob/master/doc/installation.md), the patch goes in **between obtaining the source and the
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

**Firmware:** not bundled with this patch (it is a proprietary
Intel/RealSense, Inc. binary).
The CMake configure step resolves it like this: a SHA1-verified cache at
`<repo-parent>/.fw-cache/target.mvcmd` (override the directory with
`T265_FW_CACHE`) is used when present; otherwise you must provide it
explicitly; `install-t265-patch.sh --build` prompts for it, or pass
`--fw <file>` / `--fw-source <url|path>`, or set `T265_FW_SOURCE` to a URL
(`http://`, `https://`, `file://`) or a local file path. The image is
SHA1-verified (v0.2.0.951) and cached, so rebuilds work offline.

## Reverting

```sh
bash install-t265-patch.sh --repo /path/to/librealsense --unapply
```

(after a commit of the patch: `git reset --hard HEAD~1`)

## Related projects

* [`ntsarb/realsense-ros-t265-v4.59.1`](https://github.com/ntsarb/realsense-ros-t265-v4.59.1) — restores T265 support to the `realsense2_camera` ROS 2 wrapper (4.59.1).
* [`ntsarb/T265-demo`](https://github.com/ntsarb/T265-demo) — a Qt6 viewer for the T265 (3-D trajectory, fisheye images, IMU strips, CSV export); works directly with the SDK or with the wrapper's ROS 2 topics.

## license
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/
