# Third-Party Notices

## LAME

CleanFile uses LAME 3.100.3 for optional MP3 encoding.

- Project: <https://github.com/BB9z/LAME-xcframework>
- Upstream: <https://lame.sourceforge.io/>
- License: GNU Lesser General Public License version 2.1 (LGPL-2.1)
- Exact package version: `3.100.3`
- Exact source tag: <https://github.com/BB9z/LAME-xcframework/tree/3.100.3>

The Swift Package uses a checksum-verified XCFramework built from the source in
the tagged repository. CleanFile does not enable FFmpeg, GPL codecs, or
non-free codecs as part of this integration.

Before distributing a build containing LAME, the release process must:

1. Include the complete LGPL-2.1 license text with the distributed application.
2. Show the LAME attribution and license in the app's legal/about interface.
3. Keep the exact corresponding LAME source and build instructions available.
4. Have counsel or the publisher confirm the relinking requirements that apply
   to the shipped Apple-platform binary.

This notice documents the dependency and does not replace the license text or
legal review.
