#!/bin/bash
set -e

# Function to update DSpace configurations from environment variables
update_dspace_configs() {
  echo "Updating DSpace configurations based on environment variables..."
  
  # Database connection
  if [ -n "$DSPACE_DB_URL" ]; then
    sed -i "s|^db.url.*$|db.url = $DSPACE_DB_URL|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  if [ -n "$DSPACE_DB_USER" ]; then
    sed -i "s|^db.username.*$|db.username = $DSPACE_DB_USER|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  if [ -n "$DSPACE_DB_PASSWORD" ]; then
    sed -i "s|^db.password.*$|db.password = $DSPACE_DB_PASSWORD|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  # Mail configuration
  if [ -n "$DSPACE_MAIL_SERVER" ]; then
    sed -i "s|^mail.server.*$|mail.server = $DSPACE_MAIL_SERVER|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  if [ -n "$DSPACE_MAIL_SERVER_PORT" ]; then
    sed -i "s|^mail.server.port.*$|mail.server.port = $DSPACE_MAIL_SERVER_PORT|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  if [ -n "$DSPACE_MAIL_FROM_ADDRESS" ]; then
    sed -i "s|^mail.from.address.*$|mail.from.address = $DSPACE_MAIL_FROM_ADDRESS|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  # Base URL
  if [ -n "$DSPACE_BASE_URL" ]; then
    sed -i "s|^dspace.server.url.*$|dspace.server.url = $DSPACE_BASE_URL/server|g" ${DSPACE_HOME}/config/local.cfg
    sed -i "s|^dspace.ui.url.*$|dspace.ui.url = $DSPACE_BASE_URL|g" ${DSPACE_HOME}/config/local.cfg
  fi
  
  # Handle other environment variables using a pattern-matching approach
  # This processes any environment variable that starts with "dspace__P__"
  # For example, dspace__P__solr__P__server would update solr.server in local.cfg
  for var in $(env | grep '^dspace__P__' | cut -d= -f1); do
    # Replace "__P__" with "." to create the property name
    prop_name=$(echo "$var" | sed 's/^dspace__P__//g' | sed 's/__P__/./g')
    prop_value="${!var}"
    
    # Update the property in local.cfg
    if grep -q "^$prop_name" ${DSPACE_HOME}/config/local.cfg; then
      sed -i "s|^$prop_name.*$|$prop_name = $prop_value|g" ${DSPACE_HOME}/config/local.cfg
    else
      echo "$prop_name = $prop_value" >> ${DSPACE_HOME}/config/local.cfg
    fi
  done
  
  echo "Configuration update complete."
}

# Wait for database to be ready
wait_for_db() {
  echo "Waiting for database to be ready..."
  host=$(echo $DSPACE_DB_URL | sed -E 's/^.*\/\/([^:\/]+).*$/\1/')
  
  if [ -z "$host" ]; then
    echo "Could not extract database host from DSPACE_DB_URL"
    return 1
  fi
  
  until nc -z "$host" 5432; do
    echo "Database is unavailable - sleeping"
    sleep 2
  done
  
  echo "Database is up - continuing"
}

# Check if we need to initialize DSpace (create admin account, etc.)
initialize_dspace() {
  # Check if admin user already exists by trying a simple query
  echo "Checking if DSpace needs initialization..."
  if ! ${DSPACE_HOME}/bin/dspace database test > /dev/null 2>&1; then
    echo "Running database schema migrations..."
    ${DSPACE_HOME}/bin/dspace database migrate
  fi
  
  # Check if admin account needs to be created
  if [ -n "$DSPACE_ADMIN_EMAIL" ] && [ -n "$DSPACE_ADMIN_PASS" ]; then
    if ! ${DSPACE_HOME}/bin/dspace user --email "$DSPACE_ADMIN_EMAIL" > /dev/null 2>&1; then
      echo "Creating administrator account..."
      ${DSPACE_HOME}/bin/dspace create-administrator -e "$DSPACE_ADMIN_EMAIL" \
        -f "${DSPACE_ADMIN_FIRSTNAME:-Admin}" \
        -l "${DSPACE_ADMIN_LASTNAME:-User}" \
        -p "$DSPACE_ADMIN_PASS" \
        -c "${DSPACE_ADMIN_LANGUAGE:-en}"
      echo "Administrator account created."
    else
      echo "Administrator account already exists."
    fi
  fi
  
  # Initialize search indexes if needed
  if [ ! -d "${DSPACE_HOME}/solr/search/data" ]; then
    echo "Initializing search indexes..."
    ${DSPACE_HOME}/bin/dspace index-discovery -b
    echo "Search indexes initialized."
  fi
}

# Main execution
echo "Starting DSpace..."

# Update configuration from environment variables
update_dspace_configs

# Wait for database 
if [ -n "$DSPACE_DB_URL" ]; then
  wait_for_db
fi

# Initialize if needed
initialize_dspace

# Start Tomcat
echo "Starting Tomcat..."
exec "$@"