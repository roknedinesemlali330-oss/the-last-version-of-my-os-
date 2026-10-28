#!/bin/sh
# Start the MyOS shell. If it dies within 5 seconds (for example because of
# an error in the file), start the previous stable shell instead.
start=$(date +%s)
qs -p /etc/myos/shell.qml
now=$(date +%s)
if [ $((now - start)) -lt 5 ]; then
  exec qs -p /etc/myos/stable/shell.qml
fi
