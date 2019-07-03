#!/usr/bin/env bash

log_info "Using configuration file: configs/mender_convert_config"
source configs/mender_convert_config

for config in "$@"; do
  log_info "Using configuration file: ${config}"
  source ${config}
done
