#!/usr/bin/env bash

if [[ -z "${SINGLE_FLIGHT_LOCK_DIRS+x}" ]]; then
  SINGLE_FLIGHT_LOCK_DIRS=()
fi

function single_flight_write_owner_file() {
  local lock_dir="$1"
  local owner_file="$lock_dir/owner"

  {
    printf 'pid=%s\n' "$$"
    printf 'script=%s\n' "${0##*/}"
    printf 'cwd=%s\n' "$PWD"
    printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$owner_file"
}

function single_flight_owner_value() {
  local owner_file="$1"
  local key="$2"

  [[ -f "$owner_file" ]] || return 1
  sed -n "s/^${key}=//p" "$owner_file" | head -n 1
}

function single_flight_owner_suffix() {
  local owner_file="$1"
  local pid script started_at

  pid="$(single_flight_owner_value "$owner_file" pid || true)"
  script="$(single_flight_owner_value "$owner_file" script || true)"
  started_at="$(single_flight_owner_value "$owner_file" started_at || true)"

  if [[ -z "$pid" && -z "$script" && -z "$started_at" ]]; then
    return 0
  fi

  printf ' (pid=%s' "${pid:-unknown}"
  if [[ -n "$script" ]]; then
    printf ', script=%s' "$script"
  fi
  if [[ -n "$started_at" ]]; then
    printf ', started_at=%s' "$started_at"
  fi
  printf ')'
}

function single_flight_acquire() {
  local lock_dir="$1"
  local label="$2"
  local owner_file="$lock_dir/owner"

  mkdir -p "$(dirname "$lock_dir")"

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      single_flight_write_owner_file "$lock_dir"
      SINGLE_FLIGHT_LOCK_DIRS+=("$lock_dir")
      return 0
    fi

    local existing_pid=""
    existing_pid="$(single_flight_owner_value "$owner_file" pid || true)"

    if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
      rm -rf "$lock_dir"
      continue
    fi

    echo "${label} is already running$(single_flight_owner_suffix "$owner_file")." >&2
    return 1
  done
}

function single_flight_release_all() {
  local index

  for (( index=${#SINGLE_FLIGHT_LOCK_DIRS[@]}-1; index>=0; index-- )); do
    rm -rf "${SINGLE_FLIGHT_LOCK_DIRS[index]}" 2>/dev/null || true
  done

  SINGLE_FLIGHT_LOCK_DIRS=()
}
