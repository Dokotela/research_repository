# DSpace Production Setup Guide

This guide will help you set up a production-ready DSpace instance using Docker containers. The provided configuration addresses the concerns mentioned in the original DSpace Docker documentation that their images are not production-ready.

## Prerequisites

- A server with Docker and Docker Compose installed
- At least 4GB RAM, 2 CPU cores recommended
- At least 50GB of storage (more depending on your repository size)
- Domain name with SSL certificate for production use

## Project Structure

Create the following directory structure for your production DSpace setup:

```
dspace-production/
├── .env                        # Environment variables (sensitive information)
├── docker-compose.yml          # Main Docker Compose configuration
├── backup.sh                   # Backup script
├── nginx/
│   ├── conf.d/                 # NGINX configuration
│   │   └── dspace.conf
│   └── ssl/                    # SSL certificates
│       ├── dspace.crt
│       └── dspace.key
├── config/                     # Custom DSpace configuration
│   └── local.cfg               # Your local configuration overrides
└── db-backups/                 # Directory for database backups
```

## Step 1: Prepare Configuration Files

1. Place all the provided configuration files in their respective directories.
2. Modify the `.env` file with your actual sensitive information.
3. Update the NGINX configuration in `nginx/conf.d/dspace.conf` to match your domain name.
4. Place your SSL certificates in the `nginx/ssl/` directory.

## Step 2: Customize DSpace Configuration

Create a `config/local.cfg` file with your custom DSpace configuration options:

```properties
# DSpace local configuration
dspace.name = My Institution Repository
dspace.server.url = https://dspace.example.com/server
dspace.ui.url = https://dspace.example.com

# Database settings are handled through environment variables

# Email configuration
mail.server = ${MAIL_SERVER}
mail.server.port = ${MAIL_PORT}
mail.from.address = ${MAIL_FROM}
mail.registration.notify = ${ADMIN_EMAIL}

# File size limits for uploads
upload.max = 2000000000
```

## Step 3: Build and Start DSpace

1. Build the custom DSpace images:

```bash
docker compose build
```

2. Start the DSpace services in production mode:

```bash
docker compose up -d
```

3. Monitor logs during startup:

```bash
docker compose logs -f
```

## Step 4: Security Hardening

After your DSpace instance is running, follow these additional security steps:

1. **Set up a firewall**:
   
   ```bash
   # Allow only necessary ports
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 22/tcp
   sudo ufw enable
   ```

2. **Set up automatic security updates**:

   ```bash
   # For Ubuntu/Debian
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure unattended-upgrades
   ```

3. **Regular backups**:
   
   ```bash
   # Make the backup script executable
   chmod +x backup.sh
   
   # Set up a daily cron job
   echo "0 2 * * * $(pwd)/backup.sh" | sudo tee -a /etc/crontab
   ```

## Step 5: Monitoring and Maintenance

1. **Set up container monitoring**:
   
   Consider using a monitoring solution like Prometheus with Grafana, or a simpler option like Portainer.

2. **Log rotation**:
   
   Ensure logs don't fill up your disk space:

   ```bash
   # Check if logrotate is installed
   sudo apt install logrotate
   
   # Create a logrotate configuration
   sudo nano /etc/logrotate.d/docker-dspace
   ```

   Add the following configuration:

   ```
   /var/lib/docker/containers/*/*.log {s
       rotate 7
       daily
       compress
       missingok
       delaycompress
       copytruncate
   }
   ```

## Maintenance Tasks

### Updating DSpace

When a new version of DSpace is released:

1. Update your Dockerfile to reference the new version
2. Rebuild your images:
   ```bash
   docker compose build
   ```
3. Take a backup before upgrading:
   ```bash
   ./backup.sh
   ```
4. Update your containers:
   ```bash
   docker compose down
   docker compose up -d
   ```

### Database Maintenance

Regularly perform database optimization:

```bash
# Connect to the PostgreSQL container
docker compose exec dspacedb bash

# Connect to the database
psql -U dspace

# Run vacuum analysis
VACUUM ANALYZE;

# Exit
\q
exit
```

## Troubleshooting

### Container fails to start

Check the logs:
```bash
docker compose logs dspace
```

### Database connection issues

Verify the database container is running and connection settings are correct:
```bash
docker compose logs dspacedb
```

### Performance issues

Monitor resource usage:
```bash
docker stats
```

Consider adjusting the resource limits in the `docker-compose.yml` file based on your server capacity.

## Conclusion

You now have a production-ready DSpace instance running in Docker containers. This setup addresses the security, backup, and configuration concerns mentioned in the original DSpace Docker documentation.

Remember to:
- Regularly backup your data
- Keep your system updated
- Monitor resource usage
- Check logs for any errors or warnings

For additional support, refer to the official DSpace documentation or community forums.