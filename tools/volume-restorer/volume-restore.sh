#!/bin/bash
# Requirement: JQ library

# This is a script to be used in conjunction with our volume backup scripts
# Its purpose is to restore volumes from a tarball
# while also restoring the labels used by docker as metadata for volumes

# Usage: script name <tar.gz file made by our volume archiver tool>

# Setting a couple of constants for later changing
archive_prefix=de-erpnext_
archive_postfix=_backup
file_postfix=_volume_info.json

# Check if the tarball file is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <tarball_file>"
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
trap 'rm -rf "$temp_dir"' EXIT

# Extract the contents of the tarball into the temporary directory
sudo tar --same-owner -p -zxf "$tarball_file" -C "$temp_dir"

# Pulling our data volume name
volume_name=$(echo "$tarball_file" | grep -oP "${archive_prefix}\K.*?(?=${archive_postfix})")

#Specify the metadata file path in the temporary directory
metadata_file="$temp_dir/destination/$archive_prefix$volume_name$file_postfix"

# Check if the metadata file exists
if [ -f "$metadata_file" ]; then
    # Extract labels from metadata file
    labels=$(jq -r '.[0].Labels | to_entries | map("--label \(.key)=\(.value)") | .[]' $metadata_file)
else
    labels=""
fi

# Remove our little custom metadata file
sudo rm -r $temp_dir/destination

#Make our volume with our 
docker volume create $labels $archive_prefix$volume_name

docker run --rm \
    -v $temp_dir:/archive \
    -v $archive_prefix$volume_name:/target \
    alpine \
    sh -c "cp -aR /archive/* /target/"

sudo rm -r $temp_dir

echo "Volume '$volume_name' restored from '$tarball_file'"