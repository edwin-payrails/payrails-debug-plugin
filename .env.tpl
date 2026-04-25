# Grafana MCP credentials and config
# This template is filled in via 1Password CLI:
#   op inject -i .env.tpl -o .env
# The resulting .env should NOT be committed (see .gitignore).

GRAFANA_USERNAME="op://Employee/Edwin Grafana/username"
GRAFANA_PASSWORD="op://Employee/Edwin Grafana/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
