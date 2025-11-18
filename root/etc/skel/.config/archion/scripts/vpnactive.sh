#!/bin/bash

if ip link show tun0 &>/dev/null; then
    echo "true"
    exit 0
else
    echo "false"
    exit 1
fi