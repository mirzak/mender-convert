#!/bin/bash

#    Copyright 2018 Northern.tech AS
#    Copyright 2018 Piper Networks Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
output_dir=${MENDER_CONVERSION_OUTPUT_DIR:-${application_dir}}/output

set -e

echo "Running: $(basename $0)"

if [ ! -d ${output_dir} ] || [ ! -d ${output_dir}/rootfs ]; then
    echo "Missing output directory content."
    echo "You must run stage-1 script before attempting to run this."
    exit 1
fi

# Populate root file-system with application specific changes
