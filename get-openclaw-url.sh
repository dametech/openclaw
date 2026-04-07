#!/bin/bash

# OpenClaw Control UI URL Generator
# Returns the full URL with authentication token for accessing the Control UI

OPENCLAW_IP="<openclaw-private-ip>"
OPENCLAW_TOKEN="<YOUR-OPENCLAW-TOKEN>"

# Output the complete URL
echo "https://${OPENCLAW_IP}/?token=${OPENCLAW_TOKEN}"
