#!/bin/bash
# DSpace 8.1 Production Update Script
# Safely updates DSpace configuration and performs necessary maintenance tasks
# Last updated: 2025-04-01

# Enable strict error handling
set -e

# Define constants
DSPACE_HOME=${DSPACE_HOME:-/dspace}
CONFIG_DIR="${DSPACE_HOME}/config"
CUSTOM_CONFIG_DIR="/dspace-config"
LOG_DIR="${DSPACE_HOME}/log"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
UPDATE_LOG="${LOG_DIR}/update_${TIMESTAMP}.log"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"
touch "${UPDATE_LOG}"
exec > >(tee -a "${UPDATE_LOG}") 2>&1

# Print banner
echo "===================================================================="
echo "DSpace 8.1 Production Update Process"
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

# Function to apply custom configurations
apply_custom_configs() {
  log "INFO" "Checking for custom configurations..."
  
  # Check if custom configuration directory exists
  if [ -d "$CUSTOM_CONFIG_DIR" ]; then
    log "INFO" "Found custom configuration directory. Applying custom configurations..."
    
    # Make backup of original configs
    BACKUP_DIR="${CONFIG_DIR}/backup_${TIMESTAMP}"
    log "INFO" "Creating backup of current configurations to ${BACKUP_DIR}/"
    mkdir -p "${BACKUP_DIR}"
    cp -r "${CONFIG_DIR}"/* "${BACKUP_DIR}/"
    
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
    log "INFO" "No custom configuration directory found at $CUSTOM_CONFIG_DIR. Skipping custom configuration update."
  fi
}

# Function to apply environment variable overrides
apply_env_vars() {
  log "INFO" "Applying environment variable overrides to configuration..."
  
  # Find all environment variables prefixed with DSPACE_CFG_
  env | grep "^DSPACE_CFG_" | while read -r env_var; do
    # Extract the property name by removing prefix and converting __ to .
    var_name=${env_var%%=*}
    var_value=${env_var#*=}
    prop_name=${var_name#DSPACE_CFG_}
    prop_name=$(echo "$prop_name" | sed 's/__P__/./g')
    
    log "INFO" "Setting $prop_name = $var_value"
    
    # Find which config file contains this property
    config_file="${CONFIG_DIR}/local.cfg"
    if ! grep -q "$prop_name" "$config_file"; then
      if grep -q "$prop_name" "${CONFIG_DIR}/dspace.cfg"; then
        config_file="${CONFIG_DIR}/dspace.cfg"
      else
        # If property not found in either, add to local.cfg
        echo "$prop_name = $var_value" >> "$config_file"
        continue
      fi
    fi
    
    # Update the property in the appropriate file
    sed -i "s|^[[:space:]]*$prop_name[[:space:]]*=.*$|$prop_name = $var_value|g" "$config_file"
  done
  
  log "INFO" "Environment variable overrides applied."
}

# Function to fix permissions
fix_permissions() {
  log "INFO" "Ensuring correct permissions on DSpace files..."
  
  # Ensure dspace user owns config files
  chown -R dspace:dspace "${CONFIG_DIR}"
  chmod -R u+rw "${CONFIG_DIR}"
  
  # Ensure dspace user owns assetstore
  if [ -d "${DSPACE_HOME}/assetstore" ]; then
    chown -R dspace:dspace "${DSPACE_HOME}/assetstore"
  fi
  
  # Ensure dspace user owns log directory
  chown -R dspace:dspace "${LOG_DIR}"
  
  log "INFO" "Permissions updated."
}

# Function to update DSpace
update_dspace() {
  log "INFO" "Performing DSpace update tasks..."
  
  # Check if Tomcat is running and stop it if needed
  if docker exec dspace ps -ef | grep -q "[c]atalina"; then
    log "INFO" "Stopping Tomcat before update..."
    docker exec dspace ${CATALINA_HOME}/bin/shutdown.sh
    sleep 10
  fi
  
  # Run database migrations if needed
  log "INFO" "Checking for database updates..."
  if docker exec dspace ${DSPACE_HOME}/bin/dspace database info | grep -q "upgrades available"; then
    log "INFO" "Database updates available. Running migrations..."
    docker exec dspace ${DSPACE_HOME}/bin/dspace database migrate
    log "INFO" "Database migrations completed."
  else
    log "INFO" "Database is up to date."
  fi
  
  # Re-index discovery if requested
  if [ "${REINDEX_DISCOVERY:-false}" = "true" ]; then
    log "INFO" "Re-indexing DSpace discovery..."
    docker exec dspace ${DSPACE_HOME}/bin/dspace index-discovery -b
    log "INFO" "Re-indexing completed."
  fi
  
  # Vacuum database if requested
  if [ "${VACUUM_DATABASE:-false}" = "true" ]; then
    log "INFO" "Vacuuming database..."
    docker exec dspacedb vacuumdb -z -d dspace -U dspace
    log "INFO" "Database vacuum completed."
  fi
  
  # Start Tomcat if it was stopped
  if [ "${RESTART_TOMCAT:-true}" = "true" ]; then
    log "INFO" "Starting Tomcat..."
    docker exec dspace ${CATALINA_HOME}/bin/startup.sh
    log "INFO" "Tomcat started."
  fi
}

# Function to perform cleanup tasks
perform_cleanup() {
  log "INFO" "Performing cleanup tasks..."
  
  # Clean up old log files
  log "INFO" "Cleaning up old log files..."
  LOG_RETENTION=${LOG_RETENTION:-14}
  find "${LOG_DIR}" -name "*.log" -type f -mtime +${LOG_RETENTION} -delete
  log "INFO" "Removed log files older than ${LOG_RETENTION} days."
  
  # Clean up old config backups
  log "INFO" "Cleaning up old configuration backups..."
  CONFIG_BACKUP_RETENTION=${CONFIG_BACKUP_RETENTION:-7}
  find "${CONFIG_DIR}/backup_*" -type d -mtime +${CONFIG_BACKUP_RETENTION} -exec rm -rf {} \; 2>/dev/null || true
  log "INFO" "Removed configuration backups older than ${CONFIG_BACKUP_RETENTION} days."
  
  # Clean temp files
  log "INFO" "Cleaning temporary files..."
  if [ -d "${DSPACE_HOME}/upload" ]; then
    find "${DSPACE_HOME}/upload" -type f -mtime +2 -delete
    log "INFO" "Removed temporary upload files older than 2 days."
  fi
}

# Function to check update status
check_update_status() {
  log "INFO" "Verifying update status..."
  
  # Check Tomcat status
  if [ "${RESTART_TOMCAT:-true}" = "true" ]; then
    if docker exec dspace ps -ef | grep -q "[c]atalina"; then
      log "INFO" "Tomcat is running."
    else
      log "ERROR" "Tomcat failed to start after update!"
      return 1
    fi
  fi
  
  # Check DSpace REST API
  log "INFO" "Testing DSpace REST API..."
  if curl -s -f http://localhost:8080/server/api/core/metadatafields > /dev/null; then
    log "INFO" "DSpace REST API is responding correctly."
  else
    log "WARNING" "DSpace REST API is not responding. Update may not be fully applied."
  fi
  
  # Report update summary
  log "INFO" "Update process completed successfully."
  log "INFO" "Log file: ${UPDATE_LOG}"
  log "INFO" "Configuration backup: ${BACKUP_DIR}"
}

# Main execution
log "INFO" "Starting DSpace 8.1 update process..."

# Apply custom configurations
apply_custom_configs

# Apply environment variable overrides
apply_env_vars

# Fix permissions
fix_permissions

# Update DSpace
update_dspace

# Perform cleanup
perform_cleanup

# Check update status
check_update_status

# Log update completion
log "INFO" "DSpace 8.1 update process completed at $(date)"
echo "===================================================================="
log "INFO" "Update log saved to: ${UPDATE_LOG}"
echo "===================================================================="

exit 0