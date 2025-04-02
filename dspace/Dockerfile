# Production-ready Dockerfile for DSpace
# Uses multi-stage build for optimized size and security

# Build stage
FROM maven:3.8-openjdk-11 AS build

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set build arguments
ARG DSPACE_VERSION=7.5
ARG DSPACE_SRC_DIR=/dspace-src

# Clone source code
WORKDIR /tmp
RUN git clone --depth 1 --branch dspace-${DSPACE_VERSION} https://github.com/DSpace/DSpace.git ${DSPACE_SRC_DIR}

# Build DSpace
WORKDIR ${DSPACE_SRC_DIR}
# Optional: Copy custom configurations or modules here if needed
# COPY ./local.cfg ./dspace/config/local.cfg
# COPY ./modules/ ./dspace-api/src/main/java/org/dspace/

# Build DSpace with selected profiles and options
RUN mvn package -Dmirage2.on=true -Dmirage2.deps.included=false -P!dspace-solr

# Runtime stage
FROM tomcat:9-jdk11

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl procps nano && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV CATALINA_OPTS="-Xmx2048m -Xms1024m -XX:+UseG1GC -XX:+UseStringDeduplication"
ENV JAVA_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8"
ENV DSPACE_HOME=/dspace
ENV CATALINA_BASE=/usr/local/tomcat
ENV CATALINA_HOME=/usr/local/tomcat

# Add a non-root user to run Tomcat
RUN groupadd -r dspace && \
    useradd -r -g dspace -d ${DSPACE_HOME} -s /bin/bash dspace

# Create necessary directories
RUN mkdir -p ${DSPACE_HOME}/config && \
    mkdir -p ${DSPACE_HOME}/log && \
    mkdir -p ${DSPACE_HOME}/assetstore && \
    mkdir -p ${DSPACE_HOME}/solr && \
    mkdir -p ${CATALINA_BASE}/webapps && \
    mkdir -p ${CATALINA_BASE}/logs

# Remove default Tomcat webapps
RUN rm -rf ${CATALINA_BASE}/webapps/*

# Copy built DSpace artifacts from build stage
COPY --from=build /dspace-src/dspace/target/dspace-installer/ /dspace-installer/
WORKDIR /dspace-installer

# Install DSpace and clean up installation files
RUN ant fresh_install && \
    rm -rf /dspace-installer

# Copy DSpace webapps to Tomcat
RUN cp -r ${DSPACE_HOME}/webapps/* ${CATALINA_BASE}/webapps/ && \
    chown -R dspace:dspace ${DSPACE_HOME} && \
    chown -R dspace:dspace ${CATALINA_BASE}/webapps && \
    chown -R dspace:dspace ${CATALINA_BASE}/logs

# Create a script to update configs at runtime
COPY update-configs.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/update-configs.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/server/api/core/metadatafields || exit 1

# Add a startup script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose the default port
EXPOSE 8080

# Set working directory
WORKDIR ${DSPACE_HOME}

# Switch to non-root user
USER dspace

# Set entry point
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["catalina.sh", "run"]