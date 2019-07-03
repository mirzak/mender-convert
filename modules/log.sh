#!/usr/bin/env bash

# This must be an absolute path, as users might call the log functions
# from sub-directories
log_file="${PWD}/work/convert.log"

# Log the given message at the given level.
function log {
  local -r level="$1"
  local -r message="$2"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local -r script_name="$(basename "$0")"
  >&2 echo -e "${timestamp} [${level}] [$script_name] ${message}" | tee -a ${log_file}
}

function local_log_debug {
  local -r level="DEBUG"
  local -r message="$1"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local -r script_name="$(basename "$0")"
  echo -e "${timestamp} [${level}] [$script_name] ${message}" >> ${log_file}
}

# Log the given message at DEBUG level.
function log_debug {
  local -r message="$1"
  local_log_debug "$message"
}

# Log the given message at INFO level.
function log_info {
  local -r message="$1"
  log "INFO" "$message"
}

# Log the given message at WARN level.
function log_warn {
  local -r message="$1"
  log "WARN" "$message"
}

# Log the given message at FATAL level.
function log_fatal {
  local -r message="$1"
  log "FATAL" "$message"
  exit 1
}
