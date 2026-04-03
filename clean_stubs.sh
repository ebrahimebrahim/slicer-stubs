#!/usr/bin/env bash
#
# Remove all generated type stubs (.pyi files and stub directories).
#
# Usage:
#   ./clean_stubs.sh [output-dir]
#
# If output-dir is omitted, defaults to the directory containing this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR}"

echo "Cleaning generated stubs in $OUTPUT_DIR..."

find "$OUTPUT_DIR" -name '*.pyi' -delete
rm -rf "$OUTPUT_DIR/slicer" "$OUTPUT_DIR/vtkmodules"

echo "Done."
