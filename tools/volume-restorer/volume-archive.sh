#!/bin/bash

# Script to archive a particular volume along with its metadata 
# It can be used in conjunction with the volume-unarchive tool to restore a volume

# Script will generate a metadata file buried in the tar file for later use in rebuilding the volume

# Start off by doing some arguments housekeeping
if [ -z "$1" ]; then
    echo "Bad arguments"
    echo "Usage: $0 <volume name>"
    exit 1
fi

# Setting up text labels for our backups
volume_name="$1"
backup_label_suffix=$(date +"_backup_%y-%m-%d_%H-%M")
backup_dir_suffix=$(date +"backup_%y-%m-%d")
backup_dir="./$backup_dir_suffix"

# Check to make sure the volume exists
if ! docker volume inspect "$volume_name" &> /dev/null; then
    echo "Error: No volume by the name of '$volume_name'."
    exit 1
fi

# Check if the directory already exists and create it if it doesn't
if [ ! -d "$backup_dir" ]; then
    mkdir "$backup_dir"
    echo "Created directory: $backup_dir"
else
    echo "Adding to an existing backup directory"
fi

# Define the backup file name
backup_file="${volume_name}${backup_label_suffix}.tar.gz"

# Grab our volume info & shove it into a json file
volume_info=$(docker volume inspect "$volume_name")
(echo "$volume_info" > "${backup_dir}/${volume_name}_volume_info.json")

# Create a tar.gz backup of the volume
docker run --rm \
    -v ${volume_name}:/origin \
    -v $backup_dir:/destination \
    alpine \
    tar -czf /destination/${backup_file} -C /origin . /destination/"${volume_name}_volume_info.json"

rm ${backup_dir}/${volume_name}_volume_info.json

echo "Backup of volume $volume_name saved to $backup_file"