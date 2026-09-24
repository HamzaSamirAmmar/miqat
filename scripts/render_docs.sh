#!/bin/bash
# Renders Docs/ screenshots offscreen — no screen-recording permission needed.
# Snapshots the real SwiftUI views via a dedicated (otherwise-skipped) test.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Docs
MIQAT_RENDER_DOCS=1 swift test --filter DocsRenderTests
