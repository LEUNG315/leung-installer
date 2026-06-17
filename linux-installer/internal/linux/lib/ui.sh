#!/usr/bin/env bash

# shellcheck source=lib/ui_render.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui_render.sh"
# shellcheck source=lib/ui_input.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui_input.sh"
# shellcheck source=lib/ui_menu.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ui_menu.sh"
