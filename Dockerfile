FROM docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.2.0AI.162.0

USER root

# Install Python dependencies system-wide
COPY requirements.txt /opt/snomed-iris/requirements.txt
RUN pip3 install -r /opt/snomed-iris/requirements.txt --quiet --break-system-packages

# Copy project source and init script
COPY module.xml /opt/snomed-iris/
COPY src /opt/snomed-iris/src/
COPY iris-init.script /opt/snomed-iris/iris-init.script

USER irisowner

# Load all classes and run installer during build
RUN iris start IRIS && \
    iris session IRIS -U USER < /opt/snomed-iris/iris-init.script && \
    iris stop IRIS quietly

# Copy MCP server config template
COPY config/mcp-config.toml /opt/iris/config/mcp-config.toml

EXPOSE 1972 52773
