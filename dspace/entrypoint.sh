#!/bin/bash
# DSpace 8.1 Production Entrypoint Script
# Enhanced version with better error handling, configuration management, and startup procedures
# Last updated: 2025-04-01

# Enable strict error handling
set -e

# Define constants
DSPACE_HOME=${DSPACE_HOME:-/dspace}
CONFIG_DIR="${DSPACE_HOME}/config"
CUSTOM_CONFIG_DIR="/dspace-config"
LOG_DIR="${DSPACE_HOME}/log"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
STARTUP_LOG="${LOG_DIR}/startup_${TIMESTAMP}.log"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"
touch "${STARTUP_LOG}"
exec > >(tee -a "${STARTUP_LOG}") 2>&1

# Print banner
echo "===================================================================="
echo "DSpace 8.1 Production Startup"
echo "Started at: $(date)"
echo "===================================================================="

# Function to log messages
log() {
  local level="$1"
  local message="$2"
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] [${level}] ${message}"
}

# Function to handle errors
handle_error() {
  local exit_code=$?
  log "ERROR" "An error occurred on line $1, exit code $exit_code"
  exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Function to update DSpace configurations from environment variables
update_dspace_configs() {
  log "INFO" "Updating DSpace configurations based on environment variables..."
  
  # Database connection
  if [ -n "$DSPACE_DB_URL" ]; then
    sed -i "s|^db.url.*$|db.url = $DSPACE_DB_URL|g" ${CONFIG_DIR}/local.cfg
  fi
  
  if [ -n "$DSPACE_DB_USER" ]; then
    sed -i "s|^db.username.*$|db.username = $DSPACE_DB_USER|g" ${CONFIG_DIR}/local.cfg
  fi
  
  if [ -n "$DSPACE_DB_PASSWORD" ]; then
    sed -i "s|^db.password.*$|db.password = $DSPACE_DB_PASSWORD|g" ${CONFIG_DIR}/local.cfg
  fi
  
  # Mail configuration
  if [ -n "$DSPACE_MAIL_SERVER" ]; then
    sed -i "s|^mail.server.*$|mail.server = $DSPACE_MAIL_SERVER|g" ${CONFIG_DIR}/local.cfg
  fi
  
  if [ -n "$DSPACE_MAIL_SERVER_PORT" ]; then
    sed -i "s|^mail.server.port.*$|mail.server.port = $DSPACE_MAIL_SERVER_PORT|g" ${CONFIG_DIR}/local.cfg
  fi
  
  if [ -n "$DSPACE_MAIL_FROM_ADDRESS" ]; then
    sed -i "s|^mail.from.address.*$|mail.from.address = $DSPACE_MAIL_FROM_ADDRESS|g" ${CONFIG_DIR}/local.cfg
  fi
  
  # Base URL
  if [ -n "$DSPACE_BASE_URL" ]; then
    sed -i "s|^dspace.server.url.*$|dspace.server.url = $DSPACE_BASE_URL/server|g" ${CONFIG_DIR}/local.cfg
    sed -i "s|^dspace.ui.url.*$|dspace.ui.url = $DSPACE_BASE_URL|g" ${CONFIG_DIR}/local.cfg
  fi
  
  # Upload configuration
  if [ -n "$UPLOAD_MAX_SIZE" ]; then
    sed -i "s|^upload.max.*$|upload.max = $UPLOAD_MAX_SIZE|g" ${CONFIG_DIR}/local.cfg
  fi
  
  # Handle prefix
  if [ -n "$HANDLE_PREFIX" ]; then
    sed -i "s|^handle.prefix.*$|handle.prefix = $HANDLE_PREFIX|g" ${CONFIG_DIR}/local.cfg
  fi
  
  # Process DSPACE_CFG_* variables
  log "INFO" "Processing DSPACE_CFG_* environment variables..."
  for var in $(env | grep '^DSPACE_CFG_' | cut -d= -f1); do
    # Extract the property name by replacing "__P__" with "."
    prop_name=$(echo "$var" | sed 's/^DSPACE_CFG_//g' | sed 's/__P__/./g')
    prop_value="${!var}"
    
    log "INFO" "Setting $prop_name = $prop_value"
    
    # Update the property in local.cfg
    if grep -q "^$prop_name" ${CONFIG_DIR}/local.cfg; then
      sed -i "s|^$prop_name.*$|$prop_name = $prop_value|g" ${CONFIG_DIR}/local.cfg
    else
      echo "$prop_name = $prop_value" >> ${CONFIG_DIR}/local.cfg
    fi
  done
  
  log "INFO" "Configuration update complete."
}

# Function to apply custom configurations
apply_custom_configs() {
  # Check if custom configuration directory exists
  if [ -d "$CUSTOM_CONFIG_DIR" ]; then
    log "INFO" "Found custom configuration directory. Applying custom configurations..."
    
    # Make backup of original configs
    log "INFO" "Creating backup of current configurations to ${CONFIG_DIR}/backup_${TIMESTAMP}/"
    mkdir -p "${CONFIG_DIR}/backup_${TIMESTAMP}"
    cp -r "${CONFIG_DIR}"/* "${CONFIG_DIR}/backup_${TIMESTAMP}/"
    
    # Copy custom configuration files
    log "INFO" "Copying custom configuration files..."
    
    # Handle local.cfg specially to merge rather than replace
    if [ -f "${CUSTOM_CONFIG_DIR}/local.cfg" ]; then
      log "INFO" "Merging custom local.cfg with existing configuration..."
      # Create temp file for merged config
      TEMP_CFG=$(mktemp)
      
      # Start with the original file
      cp "${CONFIG_DIR}/local.cfg" "$TEMP_CFG"
      
      # Read the custom file line by line
      while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*$ ]]; then
          continue
        fi
        
        # Extract property name (everything before =)
        prop_name=$(echo "$line" | sed -E 's/^([^=]+)=.*$/\1/' | xargs)
        
        # If property exists in original, replace it; otherwise, add it
        if grep -q "^[[:space:]]*$prop_name[[:space:]]*=" "$TEMP_CFG"; then
          sed -i "s|^[[:space:]]*$prop_name[[:space:]]*=.*$|$line|g" "$TEMP_CFG"
        else
          echo "$line" >> "$TEMP_CFG"
        fi
      done < "${CUSTOM_CONFIG_DIR}/local.cfg"
      
      # Replace the original with our merged version
      cp "$TEMP_CFG" "${CONFIG_DIR}/local.cfg"
      rm "$TEMP_CFG"
      log "INFO" "local.cfg has been updated with custom properties."
    fi
    
    # Copy other configuration files, excluding local.cfg
    find "${CUSTOM_CONFIG_DIR}" -type f -not -name "local.cfg" | while read -r file; do
      rel_path=${file#$CUSTOM_CONFIG_DIR/}
      target_file="${CONFIG_DIR}/${rel_path}"
      target_dir=$(dirname "$target_file")
      
      # Ensure target directory exists
      mkdir -p "$target_dir"
      
      log "INFO" "Copying $rel_path to $target_file"
      cp "$file" "$target_file"
    done
    
    log "INFO" "Custom configurations applied successfully."
  else
    log "INFO" "No custom configuration directory found at $CUSTOM_CONFIG_DIR. Using default configurations."
  fi
}

# Function to wait for database to be ready
wait_for_db() {
  log "INFO" "Waiting for database to be ready..."
  
  # Get database host from configuration
  db_url=$(grep "^db.url" ${CONFIG_DIR}/local.cfg | cut -d= -f2 | xargs)
  host=$(echo $db_url | sed -E 's/^.*\/\/([^:\/]+).*$/\1/')
  
  if [ -z "$host" ]; then
    log "ERROR" "Could not extract database host from db.url in local.cfg"
    return 1
  fi
  
  # Try to connect to the database
  timeout=180  # 3 minutes timeout
  counter=0
  until nc -z "$host" 5432 || [ $counter -ge $timeout ]; do
    log "INFO" "Database is unavailable - sleeping (${counter}s/${timeout}s)"
    sleep 2
    counter=$((counter+2))
  done
  
  if [ $counter -ge $timeout ]; then
    log "ERROR" "Database connection timed out after ${timeout} seconds"
    return 1
  fi
  
  log "INFO" "Database is up - continuing"
  
  # Additional check: can we connect with credentials?
  db_user=$(grep "^db.username" ${CONFIG_DIR}/local.cfg | cut -d= -f2 | xargs)
  db_name="dspace"
  
  log "INFO" "Testing database connection with credentials..."
  if ! PGPASSWORD=$DSPACE_DB_PASSWORD psql -h "$host" -U "$db_user" -d "$db_name" -c '\q' > /dev/null 2>&1; then
    log "WARNING" "Could not connect to the database with provided credentials. Schema initialization may fail."
  else
    log "INFO" "Successfully connected to the database."
  fi
}

# Function to initialize DSpace
initialize_dspace() {
  log "INFO" "Checking if DSpace needs initialization..."
  
  # Check if database schema exists and migrate if needed
  if ! ${DSPACE_HOME}/bin/dspace database test > /dev/null 2>&1; then
    log "INFO" "Running database schema migrations..."
    ${DSPACE_HOME}/bin/dspace database migrate
    if [ $? -ne 0 ]; then
      log "ERROR" "Database migration failed!"
      return 1
    fi
    log "INFO" "Database schema migrations completed successfully."
  else
    log "INFO" "Database schema is up to date."
  fi
  
  # Check for database registry initialization
  if ! ${DSPACE_HOME}/bin/dspace database info | grep -q 'metadata_schemas'; then
    log "INFO" "Initializing database registries..."
    ${DSPACE_HOME}/bin/dspace registry-loader -metadata
    ${DSPACE_HOME}/bin/dspace registry-loader -bitstream-formats
    log "INFO" "Database registries initialized."
  fi
  
  # Check if admin account needs to be created
  if [ -n "$DSPACE_ADMIN_EMAIL" ] && [ -n "$DSPACE_ADMIN_PASS" ]; then
    if ! ${DSPACE_HOME}/bin/dspace user --email "$DSPACE_ADMIN_EMAIL" > /dev/null 2>&1; then
      log "INFO" "Creating administrator account..."
      ${DSPACE_HOME}/bin/dspace create-administrator -e "$DSPACE_ADMIN_EMAIL" \
        -f "${DSPACE_ADMIN_FIRSTNAME:-Admin}" \
        -l "${DSPACE_ADMIN_LASTNAME:-User}" \
        -p "$DSPACE_ADMIN_PASS" \
        -c "${DSPACE_ADMIN_LANGUAGE:-en}"
      log "INFO" "Administrator account created."
    else
      log "INFO" "Administrator account already exists."
    fi
  else
    log "WARNING" "Admin credentials not provided. Skipping admin account creation."
  fi
  
  # Initialize search indexes if needed
  if [ ! -d "${DSPACE_HOME}/solr/search/data" ] || [ "$FORCE_REINDEX" = "true" ]; then
    log "INFO" "Initializing search indexes..."
    ${DSPACE_HOME}/bin/dspace index-discovery -b
    log "INFO" "Search indexes initialized."
  else
    log "INFO" "Search indexes exist. Skipping indexing."
  fi
  
  # Check assetstore directory
  if [ ! -d "${DSPACE_HOME}/assetstore" ]; then
    log "INFO" "Creating assetstore directory..."
    mkdir -p "${DSPACE_HOME}/assetstore"
    chown -R dspace:dspace "${DSPACE_HOME}/assetstore"
    log "INFO" "Assetstore directory created."
  fi
  
  # Ensure correct permissions
  log "INFO" "Setting correct permissions on DSpace directories..."
  chown -R dspace:dspace "${DSPACE_HOME}/config"
  chown -R dspace:dspace "${DSPACE_HOME}/log"
  chown -R dspace:dspace "${DSPACE_HOME}/solr"
}

# Function to check system health
check_system_health() {
  log "INFO" "Performing system health check..."
  
  # Check disk space
  disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ $disk_usage -gt 85 ]; then
    log "WARNING" "Disk usage is high (${disk_usage}%). Consider cleaning up old files."
  else
    log "INFO" "Disk usage is ${disk_usage}%, which is acceptable."
  fi
  
  # Check Java version
  java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
  log "INFO" "Java version: ${java_version}"
  
  # Check connection to Solr
  solr_url=$(grep "^solr.server" ${CONFIG_DIR}/local.cfg | cut -d= -f2 | xargs)
  if [ -n "$solr_url" ]; then
    log "INFO" "Testing connection to Solr at ${solr_url}..."
    if curl -s -f "${solr_url}" > /dev/null; then
      log "INFO" "Successfully connected to Solr."
    else
      log "WARNING" "Could not connect to Solr at ${solr_url}. Search functionality may be unavailable."
    fi
  fi
  
  # Log available memory
  mem_total=$(free -m | awk 'NR==2 {print $2}')
  mem_used=$(free -m | awk 'NR==2 {print $3}')
  mem_free=$(free -m | awk 'NR==2 {print $4}')
  log "INFO" "Memory - Total: ${mem_total}MB, Used: ${mem_used}MB, Free: ${mem_free}MB"
  
  # Log system load
  load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
  log "INFO" "System load: ${load}"
}

# Main execution
log "INFO" "Starting DSpace 8.1 initialization..."

# Apply custom configurations if present
apply_custom_configs

# Update configuration from environment variables
update_dspace_configs

# Wait for database 
wait_for_db

# Check system health
check_system_health

# Initialize DSpace if needed
initialize_dspace

# Log startup completion
log "INFO" "DSpace 8.1 initialization completed successfully."
log "INFO" "Starting Tomcat with explicit dspace.dir parameter..."
echo "===================================================================="

# CRITICAL CHANGE: Start DSpace with the explicit dspace.dir parameter
# This prevents the "URI is not hierarchical" error
exec java -jar /dspace/webapps/server-boot.jar --dspace.dir=/dspace "$@"