#!/bin/bash

# Load environment variables
source "$(dirname "$0")/../.env"

FILENAME="$1"
SOURCE_FILE="$HOME/$FILENAME"

# Check if file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: File $SOURCE_FILE does not exist"
    exit 1
fi

echo "Pushing $SOURCE_FILE to EC2..."
echo "Target: $EC2_HOST:$REMOTE_DIR/$FILENAME"

# Push file to EC2
scp -i "$KEY_FILE" "$SOURCE_FILE" "$EC2_HOST:$REMOTE_DIR/$FILENAME"

if [ $? -eq 0 ]; then
    echo "✓ File pushed successfully!"
else
    echo "✗ Failed to push file"
    exit 1
fi
