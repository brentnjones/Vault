#!/bin/bash
# Quick Vault Agent Injector Demo (5 minutes)

echo "🎯 VAULT AGENT INJECTOR - QUICK DEMO"
echo "======================================"
echo ""

# Scene 1: Current State
echo "📋 Current Application Secrets:"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

# Scene 2: Update Vault
echo "🔄 Updating secrets in Vault..."
TIMESTAMP=$(date +%H%M%S)
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="quick-demo-$TIMESTAMP" \
    password="password-$(date +%s)" \
    api_key="KEY-$TIMESTAMP" > /dev/null

echo "✅ Vault updated at $(date)"
echo ""

# Scene 3: Wait for automatic update
echo "⏱️  Waiting for automatic propagation..."
sleep 35

# Scene 4: Show results
echo "🎉 Updated Application Secrets (No Restart Required!):"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

echo "✨ Key Benefits Demonstrated:"
echo "   • Zero application code changes"
echo "   • Automatic secret updates"  
echo "   • No pod restarts required"
echo "   • Enterprise security & audit trails"