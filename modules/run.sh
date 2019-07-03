#!/usr/bin/env bash

# Run a command, capture output and log it
#
#  $1 - command to run
function run_and_log_cmd() {
  local -r cmd="${1}"

  log_debug "Running: \n\r\n\r\t ${cmd}"
  log_debug "Run result: \n\r"

  result=$(eval ${cmd})
  log_debug "${result}"
}
