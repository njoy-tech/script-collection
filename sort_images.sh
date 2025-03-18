#!/bin/bash

# =============================
# Script: sort_images.sh
# Description: 
#   - Searches the 'Source' directory and its subdirectories for image files (RAW, JPEG, JPG).
#   - Copies them to 'Dest' sorted by year and month based on EXIF data.
#   - Identifies duplicates (based on identical EXIF capture dates) and copies them to 'Duplicates' with a suffix.
#   - Copies files without EXIF data to 'No_Exif' sorted by the file's creation date.
# Prerequisites: ExifTool must be installed.
# =============================

# =============================
# Configuration
# =============================

# Directory where the script is executed
ROOT_DIR="$(pwd)"

# Source directory
SOURCE_DIR="$ROOT_DIR/Source"

# Destination directories
DEST_DIR="$ROOT_DIR/Dest"
DUPLICATES_DIR="$ROOT_DIR/Duplicates"
NO_EXIF_DIR="$ROOT_DIR/No_Exif"

# Supported file extensions (case-insensitive)
EXTENSIONS=("*.RAW" "*.raw" "*.JPEG" "*.jpeg" "*.JPG" "*.jpg")

# =============================
# Functions
# =============================

# Function to create directories if they do not exist
create_dir() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        echo "Created directory: $dir_path"
    fi
}

# Function to extract EXIF data (DateTimeOriginal)
get_exif_date() {
    local file="$1"
    # Extract DateTimeOriginal and format it to "YYYY-MM-DD_HH-MM-SS"
    exif_date=$(exiftool -DateTimeOriginal -d "%Y-%m-%d_%H-%M-%S" "$file" 2>/dev/null | awk -F': ' '{print $2}')
    echo "$exif_date"
}

# Function to extract year and month from a date string "YYYY-MM-DD_HH-MM-SS" or "YYYY-MM-DD"
extract_year_month() {
    local date_str="$1"
    # Extract year and month
    year=$(echo "$date_str" | cut -d'-' -f1)
    month=$(echo "$date_str" | cut -d'-' -f2)
    echo "$year:$month"
}

# Function to generate a unique filename with suffix in the format _01, _02, etc.
generate_unique_filename() {
    local dir="$1"
    local base="$2"
    local ext="$3"
    local counter=1

    while [ -e "$dir/${base}_$(printf "%02d" "$counter").$ext" ]; do
        ((counter++))
    done

    echo "${base}_$(printf "%02d" "$counter").$ext"
}

# Function to extract year and month from the file's creation date
get_file_creation_date() {
    local file="$1"
    # Use stat to get the modification date. Adjust options based on the operating system.
    if stat --version >/dev/null 2>&1; then
        # GNU stat (Linux)
        file_date=$(stat -c %y "$file" | cut -d' ' -f1)
    else
        # BSD stat (macOS)
        file_date=$(stat -f %Sm "$file" -t "%Y-%m-%d")
    fi
    echo "$file_date"
}

# =============================
# Main Logic
# =============================

# Check if ExifTool is installed
if ! command -v exiftool &> /dev/null
then
    echo "ExifTool is not installed. Please install it and try again."
    exit 1
fi

# Check if the Source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "The Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Create the necessary destination directories
create_dir "$DEST_DIR"
create_dir "$DUPLICATES_DIR"
create_dir "$NO_EXIF_DIR"

# Associative array to track processed EXIF dates
declare -A EXIF_MAP

# Find and process image files
find "$SOURCE_DIR" -type f \( $(printf -- '-iname %s -o ' "${EXTENSIONS[@]}" | sed 's/ -o $//') \) | while read -r file; do
    # Extract the capture date from EXIF
    exif_date_full=$(get_exif_date "$file")

    if [ -n "$exif_date_full" ]; then
        # File has EXIF data
        IFS=':' read -r exif_year exif_month <<< "$(extract_year_month "$exif_date_full")"

        # Destination path based on EXIF year and month
        dest_path="$DEST_DIR/$exif_year/$exif_month"
        create_dir "$dest_path"

        # Extract filename and extension
        filename=$(basename "$file")
        base_name="${filename%.*}"
        extension="${filename##*.}"

        # Key for tracking duplicates (using full EXIF date)
        exif_key="${exif_date_full}"

        if [ -z "${EXIF_MAP[$exif_key]}" ]; then
            # First occurrence of this EXIF date, copy to Dest
            EXIF_MAP["$exif_key"]="$base_name"
            cp "$file" "$dest_path/"
            echo "Copied file: $file -> $dest_path/"
        else
            # Duplicate detected, copy to Duplicates with suffix
            dup_path="$DUPLICATES_DIR/$exif_year/$exif_month"
            create_dir "$dup_path"

            # Original base name from Dest
            original_base="${EXIF_MAP[$exif_key]}"

            # Generate a unique filename with suffix
            new_filename=$(generate_unique_filename "$dup_path" "$original_base" "$extension")

            # Copy the file to Duplicates with the new name
            cp "$file" "$dup_path/$new_filename"
            echo "Copied duplicate: $file -> $dup_path/$new_filename"
        fi
    else
        # File lacks EXIF data, use file's creation date
        file_date=$(get_file_creation_date "$file")
        IFS=':' read -r file_year file_month <<< "$(extract_year_month "$file_date")"

        # Destination path for files without EXIF
        no_exif_path="$NO_EXIF_DIR/$file_year/$file_month"
        create_dir "$no_exif_path"

        # Copy the file to No_Exif
        cp "$file" "$no_exif_path/"
        echo "Copied file without EXIF: $file -> $no_exif_path/"
    fi
done

echo "Sorting completed."