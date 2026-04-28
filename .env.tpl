# Grafana MCP credentials and config
# This template is filled in via 1Password CLI:
#   op inject -i .env.tpl -o .env
# The resulting .env should NOT be committed (see .gitignore).
#
# Edit the references below to match your 1Password vault and item.
# Path format: vault-name/item-name/field-name

GRAFANA_USERNAME="op://<your-vault>/<your-grafana-item>/username"
GRAFANA_PASSWORD="op://<your-vault>/<your-grafana-item>/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
