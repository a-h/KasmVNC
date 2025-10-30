#!/bin/bash

set -euo pipefail

source_dir=$(dirname "$0")
"${source_dir}"/build-libjpeg-turbo
"${source_dir}"/build-webp
"${source_dir}"/build-tbb
"${source_dir}"/build-cpuid
"${source_dir}"/build-fmt