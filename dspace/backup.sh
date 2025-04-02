#!/bin/bash
# DSpace 8.1 Production Backup Script
# Enhanced version with better error handling, notifications, and environment variable support
# Last updated: 2025-04-01

# Load environment variables if .env file exists
if [ -f ./.env ]; then
    set -a
    source ./.env
    set +a
fi

# Configuration with environment variable overrides
BACKUP_DIR="${PGBACKUP_DIR:-/db-backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAX_BACKUPS="${BACKUP_RETENTION:-7}"  # Default: Keep a week's worth of backups
LOG_DIR="${BACKUP_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"
MAIL_TO="${ADMIN_EMAIL:-admin@example.com}"
SEND_EMAIL="${ENABLE_EMAIL_NOTIFICATIONS:-false}"
COMPRESSION_LEVEL=9  # Maximum compression

# Error handling
set -e  # Exit immediately if a command exits with a non-zero status
trap 'echo "ERROR: Backup failed at line $LINENO. Check the logs at ${LOG_FILE}"; send_notification "FAILED"' ERR

# Function to send email notifications
send_notification() {
    if [ "$SEND_EMAIL" = "true" ]; then
        STATUS="$1"
        SUBJECT="DSpace Backup ${STATUS} - ${TIMESTAMP}"
        BODY="DSpace backup process ${STATUS} at $(date).\nSee attached log for details."
        
        if command -v mailx > /dev/null; then
            echo -e "${BODY}" | mailx -s "${SUBJECT}" -a "${LOG_FILE}" "${MAIL_TO}"
        elif command -v mail > /dev/null; then
            echo -e "${BODY}" | mail -s "${SUBJECT}" "${MAIL_TO}" < "${LOG_FILE}"
        else
            echo "Email notification enabled but mail command not found"
        fi
    fi
}

# Create backup directories if they don't exist
mkdir -p "${BACKUP_DIR}/db"
mkdir -p "${BACKUP_DIR}/assetstore"
mkdir -p "${BACKUP_DIR}/solr"
mkdir -p "${BACKUP_DIR}/config"
mkdir -p "${LOG_DIR}"

# Start logging
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "==================================================================="
echo "Starting DSpace 8.1 backup at $(date)"
echo "Using backup directory: ${BACKUP_DIR}"
echo "Keeping last ${MAX_BACKUPS} backups"
echo "==================================================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running or not accessible."
    send_notification "FAILED"
    exit 1
fi

# Check if the required containers are running
for CONTAINER in dspace dspacedb dspacesolr; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "ERROR: Container ${CONTAINER} is not running."
        send_notification "FAILED"
        exit 1
    fi
done

# 1. Backup the database
echo "Backing up PostgreSQL database..."
DB_START_TIME=$(date +%s)
docker exec dspacedb pg_dump -U dspace dspace -F c -Z ${COMPRESSION_LEVEL} -f /tmp/dspace_db_${TIMESTAMP}.dump
docker cp dspacedb:/tmp/dspace_db_${TIMESTAMP}.dump "${BACKUP_DIR}/db/"
docker exec dspacedb rm /tmp/dspace_db_${TIMESTAMP}.dump
DB_END_TIME=$(date +%s)
DB_RUNTIME=$((DB_END_TIME - DB_START_TIME))
DB_SIZE=$(du -h "${BACKUP_DIR}/db/dspace_db_${TIMESTAMP}.dump" | cut -f1)
echo "✓ Database backup completed successfully in ${DB_RUNTIME} seconds (${DB_SIZE})"

# 2. Backup the assetstore
echo "Backing up DSpace assetstore..."
ASSET_START_TIME=$(date +%s)
docker run --rm --volumes-from dspace -v "${BACKUP_DIR}/assetstore:/backup" \
    alpine:latest tar czf "/backup/assetstore_${TIMESTAMP}.tar.gz" -C /dspace assetstore
ASSET_END_TIME=$(date +%s)
ASSET_RUNTIME=$((ASSET_END_TIME - ASSET_START_TIME))
ASSET_SIZE=$(du -h "${BACKUP_DIR}/assetstore/assetstore_${TIMESTAMP}.tar.gz" | cut -f1)
echo "✓ Assetstore backup completed successfully in ${ASSET_RUNTIME} seconds (${ASSET_SIZE})"

# 3. Backup Solr data
echo "Backing up Solr data..."
SOLR_START_TIME=$(date +%s)
docker run --rm --volumes-from dspacesolr -v "${BACKUP_DIR}/solr:/backup" \
    alpine:latest tar czf "/backup/solr_data_${TIMESTAMP}.tar.gz" -C /var/solr data
SOLR_END_TIME=$(date +%s)
SOLR_RUNTIME=$((SOLR_END_TIME - SOLR_START_TIME))
SOLR_SIZE=$(du -h "${BACKUP_DIR}/solr/solr_data_${TIMESTAMP}.tar.gz" | cut -f1)
echo "✓ Solr data backup completed successfully in ${SOLR_RUNTIME} seconds (${SOLR_SIZE})"

# 4. Backup configuration files
echo "Backing up DSpace configuration..."
CONFIG_START_TIME=$(date +%s)
docker run --rm --volumes-from dspace -v "${BACKUP_DIR}/config:/backup" \
    alpine:latest tar czf "/backup/dspace_config_${TIMESTAMP}.tar.gz" -C /dspace config
CONFIG_END_TIME=$(date +%s)
CONFIG_RUNTIME=$((CONFIG_END_TIME - CONFIG_START_TIME))
CONFIG_SIZE=$(du -h "${BACKUP_DIR}/config/dspace_config_${TIMESTAMP}.tar.gz" | cut -f1)
echo "✓ Configuration backup completed successfully in ${CONFIG_RUNTIME} seconds (${CONFIG_SIZE})"

# Create a backup manifest
MANIFEST_FILE="${BACKUP_DIR}/backup_manifest_${TIMESTAMP}.txt"
echo "DSpace 8.1 Backup Manifest - ${TIMESTAMP}" > "${MANIFEST_FILE}"
echo "Created: $(date)" >> "${MANIFEST_FILE}"
echo "=======================================================" >> "${MANIFEST_FILE}"
echo "Database: dspace_db_${TIMESTAMP}.dump (${DB_SIZE})" >> "${MANIFEST_FILE}"
echo "Assetstore: assetstore_${TIMESTAMP}.tar.gz (${ASSET_SIZE})" >> "${MANIFEST_FILE}"
echo "Solr Data: solr_data_${TIMESTAMP}.tar.gz (${SOLR_SIZE})" >> "${MANIFEST_FILE}"
echo "Configuration: dspace_config_${TIMESTAMP}.tar.gz (${CONFIG_SIZE})" >> "${MANIFEST_FILE}"
echo "=======================================================" >> "${MANIFEST_FILE}"
echo "Log file: backup_${TIMESTAMP}.log" >> "${MANIFEST_FILE}"
echo "Backup script version: 1.1" >> "${MANIFEST_FILE}"

# Clean up old backups
echo "Cleaning up old backups..."
find "${BACKUP_DIR}/db" -name "dspace_db_*.dump" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
find "${BACKUP_DIR}/assetstore" -name "assetstore_*.tar.gz" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
find "${BACKUP_DIR}/solr" -name "solr_data_*.tar.gz" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
find "${BACKUP_DIR}/config" -name "dspace_config_*.tar.gz" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
find "${BACKUP_DIR}" -name "backup_manifest_*.txt" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
find "${LOG_DIR}" -name "backup_*.log" -type f | sort -r | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm

# Generate backup report
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
BACKUP_END_TIME=$(date +%s)
BACKUP_START_TIME=$(stat -c %Y "${LOG_FILE}")
TOTAL_RUNTIME=$((BACKUP_END_TIME - BACKUP_START_TIME))

echo "==================================================================="
echo "Backup completed at $(date)"
echo "Total backup size: ${TOTAL_SIZE}"
echo "Total runtime: ${TOTAL_RUNTIME} seconds"
echo "==================================================================="
echo "Backup components:"
echo "- Database: ${DB_SIZE} (${DB_RUNTIME} seconds)"
echo "- Assetstore: ${ASSET_SIZE} (${ASSET_RUNTIME} seconds)"
echo "- Solr data: ${SOLR_SIZE} (${SOLR_RUNTIME} seconds)"
echo "- Configuration: ${CONFIG_SIZE} (${CONFIG_RUNTIME} seconds)"
echo "==================================================================="
echo "Backup manifest created at: ${MANIFEST_FILE}"
echo "Log file: ${LOG_FILE}"

# Send success notification
send_notification "SUCCESSFUL"

echo "Backup process completed successfully!"
exit 0