#!/bin/bash
# Requirement: JQ library

# This is a script to be used in conjunction with our volume backup scripts
# Its purpose is to restore volumes from a tarball
# while also restoring the labels used by docker as metadata for volumes

# NOTE - Requires sudo permissions to preserve ownerships when extracting from archives

# Usage: script_name <archive file> <optional argument>
# Arguments
    # <archive file>: the tar.gz archive file made by our archiving process (for volume metadata file
    # <optional argument

# Setting a couple of constants for later changing
archive_prefix=de-erpnext_
archive_postfix=_backup
file_postfix=_volume_info.json

# Check if we have appropriate argument counts (between 1 & 2)
if [ -z "$1" ]; then
    echo "Usage: $0 <tarball_file>"
    exit 1
elif [ "$#" -gt 2 ]; then
    echo "Error: Too many arguments provided (max 1 mandatory, 1 optional)"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install before running"
    exit 1
fi

# Check if the specified tarball file exists
tarball_file="$1"
if [ ! -f "$tarball_file" ]; then
    echo "Error: Tarball file '$tarball_file' not found."
    exit 1
fi

# Create a temporary directory that will auto remove on exit
temp_dir=$(mktemp -d)
trap 'sudo rm -rf "$temp_dir"' EXIT

# Extract the contents of the tarball into the temporary directory
sudo tar --same-owner -p -zxf "$tarball_file" -C "$temp_dir"

# Grab our metadata file
meta_file=$(find $temp_dir/destination -type f -name "*_volume_info.json")

# Check if the metadata file exists
if [ -f "$meta_file" ]; then
    labels=$(jq -r '.[0].Labels | to_entries | map("--label \(.key)=\(.value)") | .[]' $meta_file)
else
    echo "Error: Volume metadata file $meta_file not found in archive"
    exit 1
fi

# Grab chunks out of the json data, could consense this down to jus the vol_title
vol_project=$(jq -r '.[0].Labels."com.docker.compose.project"' $meta_file)
vol_name=$(jq -r '.[0].Labels."com.docker.compose.volume"' $meta_file)

#Check to see if optional second argument has been provided, if so, replace appropiate fields in the meta file instance
if [ -n "$2" ]; then
    vol_proj_override="$2"
    vol_title="${vol_proj_override}_${vol_name}"
else
    vol_title=$(jq -r '.[0]."Name"' $meta_file)
fi

# Remove our little custom metadata file
sudo rm -r $temp_dir/destination

#Make our volume with our titling
docker volume create $labels $vol_title

docker run --rm \
    -v $temp_dir:/archive \
    -v $vol_title:/target \
    alpine \
    sh -c "cp -aR /archive/* /target/"

sudo rm -r $temp_dir

echo "Volume '$vol_name' from project '$vol_project' restored as '$vol_title' from '$tarball_file'"