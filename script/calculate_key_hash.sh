#!/bin/bash

# Ensure any errors lead to a unique output to bust the cache
set -o errexit -o errtrace
error_handler() {
  echo "ERROR on line ${1}. Exit code: ${2}. TS: `date +%s.%N`"
  exit $2
}
trap 'error_handler ${LINENO} ${$?}' ERR

# First argument is cache identifier
if [ -z "$1" ]; then
  echo "${0}: Cache identifier argument not supplied"
  error_handler $((LINENO - 2)) 1
fi
CACHE_KEY=$1
shift

# Ensure at least one additional argument was supplied
if [ -z "$1" ]; then
  echo "${0}: At least one directory or file argument must be supplied"
  error_handler $((LINENO - 2)) 2
fi

# Calculate hash from files and directories supplied as arugments
HASH=`find "$@" -type f -exec md5sum {} \; | sort -k 2 | md5sum | cut -c1-32`

# Store the calculated hash and output it
mkdir -p $HOME/.session-cache-keys
echo $HASH | tee $HOME/.session-cache-keys/${CACHE_KEY}
