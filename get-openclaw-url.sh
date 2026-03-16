#!/bin/bash

# OpenClaw Control UI URL Generator
# Returns the full URL with authentication token for accessing the Control UI

OPENCLAW_IP="10.0.2.162"
OPENCLAW_TOKEN="9e56f4da7659390a5791329ff3c542452f500219e2178e00"

# Output the complete URL
echo "https://${OPENCLAW_IP}/?token=${OPENCLAW_TOKEN}"
