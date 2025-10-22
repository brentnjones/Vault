#!/bin/bash
# Quick Vault Agent Injector Demo (5 minutes)

echo "VAULT AGENT INJECTOR - QUICK DEMO"
echo "=================================="
echo ""

# Scene 1: Current State
echo "CURRENT APPLICATION SECRETS:"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

# Scene 2: Update Vault
echo "UPDATING SECRETS IN VAULT..."
TIMESTAMP=$(date +%H%M%S)
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="quick-demo-$TIMESTAMP" \
    password="password-$(date +%s)" \
    api_key="KEY-$TIMESTAMP" > /dev/null

echo "VAULT UPDATED at $(date)"
echo ""

# Scene 3: Wait for automatic update
echo "WAITING FOR AUTOMATIC PROPAGATION..."
sleep 35

# Scene 4: Show results
echo "UPDATED APPLICATION SECRETS (No Restart Required!):"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

echo "KEY BENEFITS DEMONSTRATED:"
echo "   • Zero application code changes"
echo "   • Automatic secret updates"  
echo "   • No pod restarts required"
echo "   • Enterprise security & audit trails"