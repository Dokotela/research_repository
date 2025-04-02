#!/bin/bash
# This script updates DSpace configuration files during container startup
# It ensures any custom configuration changes are properly applied

CONFIG_DIR="${DSPACE_HOME}/config"
CUSTOM_CONFIG_DIR="/dspace-config"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")

# Check if custom configuration directory exists
if [ -d "$CUSTOM_CONFIG_DIR" ]; then
    echo "Found custom configuration directory. Applying custom configurations..."
    
    # Make backup of original configs
    echo "Creating backup of current configurations to ${CONFIG_DIR}/backup_${TIMESTAMP}/"
    mkdir -p "${CONFIG_DIR}/backup_${TIMESTAMP}"
    cp -r "${CONFIG_DIR}"/* "${CONFIG_DIR}/backup_${TIMESTAMP}/"
    
    # Copy custom configuration files
    echo "Copying custom configuration files..."
    
    # Handle local.cfg specially to merge rather than replace
    if [ -f "${CUSTOM_CONFIG_DIR}/local.cfg" ]; then
        echo "Merging custom local.cfg with existing configuration..."
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
        echo "local.cfg has been updated with custom properties."
    fi
    
    # Copy other configuration files, excluding local.cfg
    find "${CUSTOM_CONFIG_DIR}" -type f -not -name "local.cfg" | while read -r file; do
        rel_path=${file#$CUSTOM_CONFIG_DIR/}
        target_file="${CONFIG_DIR}/${rel_path}"
        target_dir=$(dirname "$target_file")
        
        # Ensure target directory exists
        mkdir -p "$target_dir"
        
        echo "Copying $rel_path to $target_file"
        cp "$file" "$target_file"
    done
    
    echo "Custom configurations applied successfully."
else
    echo "No custom configuration directory found at $CUSTOM_CONFIG_DIR. Using default configurations."
fi

# Apply environment variable overrides
if [ "$APPLY_ENV_VARS" = "true" ]; then
    echo "Applying environment variable overrides to configuration..."
    
    # Find all environment variables prefixed with DSPACE_CFG_
    env | grep "^DSPACE_CFG_" | while read -r env_var; do
        # Extract the property name by removing prefix and converting __ to .
        var_name=${env_var%%=*}
        var_value=${env_var#*=}
        prop_name=${var_name#DSPACE_CFG_}
        prop_name=$(echo "$prop_name" | sed 's/__/./g')
        
        echo "Setting $prop_name = $var_value"
        
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
    
    echo "Environment variable overrides applied."
fi

# Fix permissions
echo "Ensuring correct permissions on configuration files..."
chown -R dspace:dspace "$CONFIG_DIR"
chmod -R u+rw "$CONFIG_DIR"

echo "Configuration update complete."
exit 0