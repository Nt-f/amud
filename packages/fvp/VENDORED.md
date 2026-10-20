# fvp, vendored for Linux and Windows

[fvp](https://pub.dev/packages/fvp) 0.39.1 (BSD-3-Clause, see LICENSE) plays
the daf video shiurim on Linux and Windows, where `video_player` has no
implementation of its own. It registers itself there; nothing in the app
calls it.

It is a copy rather than a pub dependency only to keep it off the other
platforms: a plugin builds into every platform its pubspec lists, and fvp's
Android, iOS and macOS parts would bundle libmdk (about 20 MB) into apps
that play video with the official `video_player`. So this copy keeps `lib/`,
`linux/`, `windows/` and `cmake/`, and its pubspec lists only `linux` and
`windows`. Nothing else is changed.

At build time `cmake/deps.cmake` downloads the libmdk SDK (with its own
FFmpeg) and the build puts it in the app bundle. libmdk is closed source;
its licence is free for Flutter apps through fvp, commercial ones included
(https://github.com/wang-bin/mdk-sdk#license).

To update: take the new release from pub.dev
(`https://pub.dev/api/archives/fvp-<version>.tar.gz`), copy those four
folders, LICENSE, README.md and CHANGELOG.md over these, and trim the new
pubspec's `platforms:` the same way.
