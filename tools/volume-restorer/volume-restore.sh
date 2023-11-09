#!/bin/sh
if [ $# -ne 1 ]; then
    echo "Correct use: $0 <backup_file.tar.gz>"
    exit 1
fi

# Create a temporary directory for data restoration
temp_dir=$(mktemp -d)

# Ensure the temporary directory was created
if [ ! -d "$temp_dir" ]; then
    echo "Error: Failed to create a temporary directory."
    exit 1
fi

backup_file_tar="$1"

# Extract the backup data to the temporary directory
tar -zxvf "$backup_file_tar" -C "$temp_dir"

export COMPOSE_PROJECT_NAME=de-erpnext

# Run the Docker Compose process for data restoration using the temporary directory
docker compose -f compose-volume.yml up #-d

# Wait for the restoration process to complete
# This will be necessary if we end up needing the -d flag
#sleep 5

# Clean up the containers and the temporary directory after restoration
docker compose -f compose-volume.yml down
rm -r "$temp_dir"

unset COMPOSE_PROJECT_NAME