#!/bin/bash

set -e

if [ "$1" = 'hub' ]; then
  shift
  exec ./bin/hub.sh "$@"
fi

exec "$@"
