#!/bin/bash
# Demo Reset Utility

echo "🔄 RESETTING VAULT AGENT INJECTOR DEMO"
echo "======================================"
echo ""

# Reset secrets to known state
echo "Resetting secrets to demo baseline..."
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="demo-user" \
    password="demo-password" \
    api_key="DEMO-KEY-READY"

echo "✅ Secrets reset in Vault"
echo ""

# Wait for propagation
echo "Waiting for secret propagation (35 seconds)..."
sleep 35

# Verify reset
echo "Demo environment ready:"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""

# Check pod status  
echo "Pod status:"
oc get pods -l app=myapp -n default
echo ""

echo "🎯 Demo environment is ready!"
echo "   • Secrets reset to baseline"
echo "   • 30-second update interval configured"
echo "   • Application pod running normally"
echo ""
echo "Available demo scripts:"
echo "   ./quick-demo.sh      - 5 minute overview"
echo "   ./technical-demo.sh  - 15 minute deep-dive"  
echo "   ./executive-demo.sh  - 3 minute business summary"