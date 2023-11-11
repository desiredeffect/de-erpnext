#!/bin/bash

# Shell script to create datestamped & labelled tarballs of volumes associated with a container
# Script will automatically ignore anonymous volumes
# Script will generate a metadata file buried in the tar file for later use in rebuilding the volume

# Start off by doing some arguments housekeeping
if [ -z "$1" ]; then
    echo "Bad arguments"
    echo "Usage: $0 <container_name>"
    exit 1
fi

# Setting up text labels for our backups
container_name="$1"
backup_label_suffix=$(date +"_backup_%y-%m-%d_%H-%M")

backup_dir="./$container_name$backup_label_suffix"

# List all volumes associated with the specified container - exit if this command goes bad
volumes=$(docker container inspect --format '{{range .Mounts}}{{.Name}} {{end}}' "$container_name")
if [ $? -ne 0 ]; then
    echo "Error: bad container or no associated volumes with '$container_name'."
    exit 1
fi

# Check if the directory already exists and create it if it doesn't
if [ ! -d "$backup_dir" ]; then
    mkdir "$backup_dir"
    echo "Created directory: $backup_dir"
else
    echo "Error: directory already exists: $backup_dir"
    exit 1
fi

# Loop through each volume and create a tar.gz backup
for volume in $volumes; do
    # Get the volume name (strip any leading/trailing whitespace)
    volume_name=$(echo "$volume" | xargs)

    # Check for & skip over anonymous volumes
    is_anon=$(docker volume inspect -f '{{.Labels}}' "$volume_name" | grep -o 'anonymous')
    if [ -n "$is_anon" ]; then
        echo "skipping anonymous volume: $volume_name"
        continue
    fi    

    # Define the backup file name
    backup_file="${volume_name}${backup_label_suffix}.tar.gz"

    volume_info=$(docker volume inspect "$volume_name")
    (echo "$volume_info" > "${backup_dir}/${volume_name}_volume_info.json")

    # Create a tar.gz backup of the volume
    docker run --rm \
        -v ${volume_name}:/origin \
        -v $backup_dir:/destination \
        alpine \
        tar -czf /destination/${backup_file} -C /origin . /destination/"${volume_name}_volume_info.json"

    echo "Backup of volume $volume_name saved to $backup_file"
done

echo "Backup process completed"