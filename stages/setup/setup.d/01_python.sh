#!/bin/bash

NAME="Python packages"

_setup() {
    local REQ_TXT="toolchain/dependencies/requirements.txt dependencies/requirements.txt"
    local REQ_FILES
    for F in ${REQ_TXT}; do
      if [[ -r ${F} ]]; then 
          REQ_FILES="${REQ_FILES} -r ${F}"
      fi
    done
    python3 -m pip install --upgrade pip
    python3 -m pip install ${REQ_FILES}
    return $?
}