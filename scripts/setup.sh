#!/usr/bin/env bash

# Define text colors
set_color() {
    declare -g "$1"="\033[$2m"
}
set_color "COLOR_INFO" "96"
set_color "COLOR_SUCCESS" "92"
set_color "COLOR_WARNING" "93"
set_color "COLOR_DANGER" "91"
set_color "COLOR_RESET" "0"

# Print messages with colors
log_message() {
    local type="$1" message="$2"
    case "$type" in
        "info") echo -e "${COLOR_INFO}${message}${COLOR_RESET}" ;;
        "success") echo -e "${COLOR_SUCCESS}${message}${COLOR_RESET}" ;;
        "warning") echo -e "${COLOR_WARNING}${message}${COLOR_RESET}" ;;
        "danger") echo -e "${COLOR_DANGER}${message}${COLOR_RESET}" ;;
        *) echo -e "${message}" ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Verify required commands
verify_dependencies() {
    local dependencies=("netstat" "sha1sum" "md5sum" "unzip")
    for cmd in "${dependencies[@]}"; do
        if ! command_exists "$cmd"; then
            log_message "danger" "Missing required command: $cmd. Please install it."
            exit 1
        fi
    done
}

# Check if required ports are free
check_ports() {
    local ports=(5432 8089 8443 8444 8446 9000 9001)
    log_message "info" "Checking required ports..."
    for port in "${ports[@]}"; do
        if netstat -lant | grep -w "$port" &>/dev/null; then
            log_message "danger" "Port $port is in use. Resolve the issue before proceeding."
            exit 1
        fi
        log_message "success" "Port $port is available."
    done
}

# Cleanup existing setup
cleanup_setup() {
    local tak_folder="tak"
    if [ -d "$tak_folder" ]; then
        log_message "warning" "Directory '$tak_folder' already exists."
        read -rp "Do you want to remove it? (y/n): " confirm
        if [[ "$confirm" =~ ^[nN] ]]; then
            log_message "danger" "Exiting setup."
            exit 1
        fi
        rm -rf "$tak_folder" /tmp/takserver
        docker volume rm --force tak-server_db_data &>/dev/null
        log_message "success" "Removed previous setup."
    fi
}

# Verify checksum of release files
verify_checksums() {
    log_message "info" "Verifying release file checksums..."
    local release_files=(*-RELEASE-*.zip)
    if [ ${#release_files[@]} -eq 0 ]; then
        log_message "danger" "No release files found. Exiting setup."
        exit 1
    fi

    for file in "${release_files[@]}"; do
        log_message "info" "File: $file"
        sha1sum "$file"
        md5sum "$file"
    done
    # Placeholder for actual checksum comparison if needed
}

# Extract release file
extract_release() {
    local release_zip="$1"
    local extract_dir="/tmp/takserver"
    log_message "info" "Extracting $release_zip to $extract_dir..."
    rm -rf "$extract_dir"
    unzip "$release_zip" -d "$extract_dir" || {
        log_message "danger" "Failed to extract $release_zip."
        exit 1
    }
    mv "$extract_dir"/*/tak ./
    log_message "success" "Extraction completed."
}

# Setup Docker containers
setup_docker() {
    local docker_compose_file="$1"
    log_message "info" "Starting Docker containers..."
    docker compose --file "$docker_compose_file" up --force-recreate -d || {
        log_message "danger" "Docker setup failed."
        exit 1
    }
    log_message "success" "Docker containers are running."
}

# Generate certificates
generate_certificates() {
    local ip="$1"
    local cert_dir="./tak/certs"
    log_message "info" "Generating certificates..."
    cd "$cert_dir" || exit 1
    ./makeRootCa.sh --ca-name CRFtakserver
    ./makeCert.sh server "$ip"
    ./makeCert.sh client admin
    cd - || exit 1
    log_message "success" "Certificates generated."
}

# Main setup logic
main() {
    verify_dependencies
    check_ports
    cleanup_setup

    log_message "info" "Looking for release file..."
    local release_file
    release_file=$(ls *-RELEASE-*.zip 2>/dev/null | head -n 1)
    if [ -z "$release_file" ]; then
        log_message "danger" "No release file found. Please place it in the current directory."
        exit 1
    fi

    verify_checksums
    extract_release "$release_file"

    local docker_compose_file="docker-compose.yml"
    if [[ $(dpkg --print-architecture) == "arm64" ]]; then
        docker_compose_file="docker-compose.arm.yml"
        log_message "info" "Using ARM64-specific Docker compose file."
    fi

    setup_docker "$docker_compose_file"

    local ip
    ip=$(hostname -I | awk '{print $1}')
    log_message "info" "Using IP address: $ip"
    generate_certificates "$ip"

    log_message "success" "Setup completed. Access the server at https://$ip:8443"
}

# Run the script
main "$@"
