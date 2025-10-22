#!/bin/bash
# Technical Deep-dive Demo (15 minutes)

echo "VAULT AGENT INJECTOR - TECHNICAL DEEP-DIVE"
echo "==========================================="
echo ""

# Architecture Overview
echo "ARCHITECTURE OVERVIEW"
echo "--------------------"
echo "Vault Server: $(oc get pods -n vault -l app.kubernetes.io/name=vault --no-headers | wc -l) pod(s)"
echo "Agent Injector: $(oc get pods -n vault -l app.kubernetes.io/name=vault-agent-injector --no-headers | wc -l) pod(s)"
echo ""

# Pod Analysis
echo "POD CONTAINER ANALYSIS"
echo "----------------------"
POD_NAME=$(oc get pods -l app=myapp -n default -o jsonpath='{.items[0].metadata.name}')
echo "Application Pod: $POD_NAME"
echo "Containers:"
echo "  • $(oc get pod $POD_NAME -n default -o jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | sed 's/^/    /')"
echo "Init Containers:"
echo "  • $(oc get pod $POD_NAME -n default -o jsonpath='{.spec.initContainers[*].name}' | tr ' ' '\n' | sed 's/^/    /')"
echo ""

# Configuration Analysis
echo "CONFIGURATION DETAILS"
echo "---------------------"
echo "Vault Agent Configuration:"
oc get pod $POD_NAME -n default -o jsonpath='{.spec.containers[?(@.name=="vault-agent")].env[?(@.name=="VAULT_CONFIG")].value}' | base64 -d | jq '.' | head -15
echo ""

# Current Secrets
echo "CURRENT SECRETS"
echo "---------------"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

# Vault Agent Logs
echo "VAULT AGENT ACTIVITY"
echo "--------------------"
echo "Recent Vault Agent logs:"
oc logs $POD_NAME -c vault-agent -n default --tail=5
echo ""

# Live Secret Update
echo "LIVE SECRET UPDATE DEMONSTRATION"
echo "--------------------------------"
BEFORE_SECRETS=$(oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt 2>/dev/null)
echo "Updating secrets at $(date)..."

TIMESTAMP=$(date +%H%M%S)
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="technical-demo-$TIMESTAMP" \
    password="tech-password-$(date +%s)" \
    api_key="TECH-KEY-$TIMESTAMP"

echo "Monitoring Vault Agent logs for template render..."
echo "Press Ctrl+C after you see the update"
oc logs $POD_NAME -c vault-agent -n default --follow --timestamps=true | grep "rendered" &
LOG_PID=$!

sleep 45
kill $LOG_PID 2>/dev/null

echo ""
echo "Updated secrets:"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

# Security Analysis
echo "SECURITY & AUDIT DETAILS"
echo "------------------------"
echo "Secret version and metadata:"
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq '.data.metadata'
echo ""

echo "Authentication method:"
oc exec vault-0 -n vault -- vault read auth/kubernetes/role/myapp | grep -E "(bound_service_account|policies|token_ttl)"
echo ""

echo "Active policy:"
oc exec vault-0 -n vault -- vault policy read myapp-policy
echo ""

# Performance Metrics
echo "PERFORMANCE METRICS"
echo "-------------------"
echo "Update Interval: 30 seconds (demo optimized)"
echo "Token TTL: 24 hours"
echo "Secret Version: $(oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq -r '.data.metadata.version')"
echo ""

echo "TECHNICAL DEEP-DIVE COMPLETE!"
echo "   Architecture: [EXPLAINED]"
echo "   Configuration: [ANALYZED]"  
echo "   Security: [DEMONSTRATED]"
echo "   Performance: [MEASURED]"