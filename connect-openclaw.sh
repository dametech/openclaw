#!/bin/bash

# SSM Port Forwarding Script for openclaw-ec2
# This script sets up port forwarding to access openclaw running on the EC2 instance

INSTANCE_ID="i-0f6dac37c87940ba9"
REGION="ap-southeast-2"
LOCAL_PORT="${1:-3978}"
REMOTE_PORT="${2:-3978}"

echo "Setting up SSM port forwarding to openclaw-ec2..."
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "Local Port: $LOCAL_PORT"
echo "Remote Port: $REMOTE_PORT"
echo ""
echo "Access openclaw at: http://localhost:$LOCAL_PORT"
echo ""
echo "Press Ctrl+C to stop the port forwarding session"
echo ""

aws ssm start-session \
    --region "$REGION" \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
