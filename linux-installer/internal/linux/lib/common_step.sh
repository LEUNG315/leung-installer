#!/usr/bin/env bash

set_current_step() {
	LEUNG_CURRENT_STEP="$1"
	[[ -n "$LEUNG_CURRENT_STEP_FILE" ]] && printf '%s\n' "$LEUNG_CURRENT_STEP" >"$LEUNG_CURRENT_STEP_FILE"
	log_info "步骤: $LEUNG_CURRENT_STEP"
}

load_current_step() {
	if [[ -n "${LEUNG_CURRENT_STEP:-}" ]]; then
		printf '%s\n' "$LEUNG_CURRENT_STEP"
		return 0
	fi
	[[ -f "$LEUNG_CURRENT_STEP_FILE" ]] || return 1
	tr -d '\n' <"$LEUNG_CURRENT_STEP_FILE"
}

run_step() {
	local step_name="$1"
	shift
	set_current_step "$step_name"
	"$@"
}
