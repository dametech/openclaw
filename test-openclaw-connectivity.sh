#!/bin/bash

# Test script to verify connectivity to openclaw from within the VPC
# Run this on any EC2 instance in the VPC (10.0.0.0/16)

OPENCLAW_IP="<openclaw-private-ip>"
OPENCLAW_PORT="3978"
HTTP_PORT="80"

echo "=================================="
echo "Testing OpenClaw Connectivity"
echo "=================================="
echo ""

# Test port 3978 (openclaw gateway)
echo "Testing port $OPENCLAW_PORT (openclaw gateway)..."
if timeout 5 bash -c "</dev/tcp/$OPENCLAW_IP/$OPENCLAW_PORT" 2>/dev/null; then
    echo "✓ Port $OPENCLAW_PORT is reachable"
    echo ""
    echo "Testing HTTP response on port $OPENCLAW_PORT..."
    curl -s -m 5 "http://$OPENCLAW_IP:$OPENCLAW_PORT" > /dev/null && echo "✓ HTTP response received" || echo "⚠ Port open but no HTTP response"
else
    echo "✗ Port $OPENCLAW_PORT is NOT reachable"
fi

echo ""

# Test port 80 (web interface)
echo "Testing port $HTTP_PORT (web interface)..."
if timeout 5 bash -c "</dev/tcp/$OPENCLAW_IP/$HTTP_PORT" 2>/dev/null; then
    echo "✓ Port $HTTP_PORT is reachable"
    echo ""
    echo "Testing HTTP response on port $HTTP_PORT..."
    curl -s -m 5 "http://$OPENCLAW_IP:$HTTP_PORT" > /dev/null && echo "✓ HTTP response received" || echo "⚠ Port open but no HTTP response"
else
    echo "✗ Port $HTTP_PORT is NOT reachable"
fi

echo ""
echo "=================================="
echo "Connection Summary"
echo "=================================="
echo "OpenClaw Gateway: http://$OPENCLAW_IP:$OPENCLAW_PORT"
echo "Web Interface:    http://$OPENCLAW_IP:$HTTP_PORT"
echo ""
