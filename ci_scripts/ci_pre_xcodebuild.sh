#!/bin/sh
set -euo pipefail

"$(cd "$(dirname "$0")" && pwd)/../scripts/build_finder_core_universal.sh"
