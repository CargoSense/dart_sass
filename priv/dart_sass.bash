#!/usr/bin/env bash

# This script was taken from the Elixir Port guide. It is used to ensure
# graceful termination of the `sass` process when it detects that stdin
# has been closed.
# Link: https://hexdocs.pm/elixir/Port.html#module-zombie-operating-system-processes
#
# This script is required until dart-sass supports listening on stdin and
# gracefully terminating when stdin is closed. There is currently a PR for
# this behaviour: https://github.com/sass/dart-sass/pull/1411
#
# Start the program in the background
exec "$@" &
pid1=$!

# Silence warnings from here on
exec >/dev/null 2>&1

# Read from stdin in the background and
# kill running program when stdin closes
exec 0<&0 $(
  while read; do :; done
  kill -KILL $pid1
) &
pid2=$!

# Clean up
wait $pid1
ret=$?
kill -KILL $pid2
exit $ret
