#!/bin/bash
# DSpace production backup script

# Configuration
BACKUP_DIR="/path/to/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAX_BACKUPS=7  # Keep a week's worth of backups
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}/db"
mkdir -p "${BACKUP_DIR}/assetstore"
mkdir -p "${BACKUP_DIR}/solr"
mkdir -p "${BACKUP_DIR}/config"

# Start logging
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "Starting DSpace backup at $(date)"

# 1. Backup the database
echo "Backing up PostgreSQL database..."
docker exec dspacedb pg_dump -U dspace dspace | gzip > "${BACKUP_DIR}/db/dspace_db_${TIMESTAMP}.sql.gz"
if [ $? -eq 0 ]; then
    echo "✓ Database backup completed successfully"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# 2. Backup the assetstore
echo "Backing up DSpace assetstore..."
docker run --rm --volumes-from dspace -v "${BACKUP_DIR}/assetstore:/backup" \
    alpine tar czf "/backup/assetstore_${TIMESTAMP}.tar.gz" /dspace/assetstore
if [ $? -eq 0 ]; then
    echo "✓ Assetstore backup completed successfully"
else
    echo "✗ Assetstore backup failed!"
    exit 1
fi

# 3. Backup Solr data (optional but recommended)
echo "Backing up Solr data..."
docker run --rm --volumes-from dspacesolr -v "${BACKUP_DIR}/solr:/backup" \
    alpine tar czf "/backup/solr_data_${TIMESTAMP}.tar.gz" /var/solr/data
if [ $? -eq 0 ]; then
    echo "✓ Solr data backup completed successfully"
else
    echo "✗ Solr data backup failed!"
    exit 1
fi

# 4. Backup configuration files
echo "Backing up DSpace configuration..."
docker run --rm --volumes-from dspace -v "${BACKUP_DIR}/config:/backup" \
    alpine tar czf "/backup/dspace_config_${TIMESTAMP}.tar.gz" /dspace/config
if [ $? -eq 0 ]; then
    echo "✓ Configuration backup completed successfully"
else
    echo "✗ Configuration backup failed!"
    exit 1
fi

# Clean up old backups
echo "Cleaning up old backups..."
cd "${BACKUP_DIR}/db" && ls -t dspace_db_*.sql.gz | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
cd "${BACKUP_DIR}/assetstore" && ls -t assetstore_*.tar.gz | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
cd "${BACKUP_DIR}/solr" && ls -t solr_data_*.tar.gz | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm
cd "${BACKUP_DIR}/config" && ls -t dspace_config_*.tar.gz | tail -n +$((MAX_BACKUPS+1)) | xargs -r rm

# Generate backup report
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
echo "Backup completed at $(date)"
echo "Total backup size: ${TOTAL_SIZE}"
echo "Backup files:"
find "${BACKUP_DIR}" -type f -name "*${TIMESTAMP}*" | sort

# Optionally, send an email notification
# mail -s "DSpace Backup Report ${TIMESTAMP}" admin@example.com < "${LOG_FILE}"

echo "Backup process completed successfully!"
exit 0