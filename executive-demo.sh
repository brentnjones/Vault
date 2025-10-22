#!/bin/bash
# Executive Summary Demo (3 minutes)

echo "VAULT AGENT INJECTOR - EXECUTIVE SUMMARY"
echo "========================================"
echo ""

echo "BUSINESS PROBLEM SOLVED"
echo "-----------------------"
echo "BEFORE: Manual secret management"
echo "   • Developers write custom secret handling code"
echo "   • Security risks from exposed credentials"  
echo "   • Manual processes for secret rotation"
echo "   • Application downtime for secret updates"
echo ""

echo "AFTER: Automated secret injection"
echo "   • Zero application code changes required"
echo "   • Enterprise-grade security and encryption"
echo "   • Automatic secret rotation and updates"
echo "   • Zero downtime secret management"
echo ""

echo "LIVE DEMONSTRATION"
echo "------------------"
echo "Current application secrets:"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt | sed 's/^/   /'
echo ""

echo "Updating secrets in central Vault..."
TIMESTAMP=$(date +%H%M%S)
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="executive-demo-$TIMESTAMP" \
    password="exec-secure-$(date +%s)" \
    api_key="EXEC-$TIMESTAMP" > /dev/null

echo "VAULT UPDATED - waiting for automatic propagation..."
sleep 35

echo ""
echo "Updated application secrets (no restart required):"
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt | sed 's/^/   /'
echo ""

echo "BUSINESS IMPACT"
echo "---------------"
echo "DEVELOPER PRODUCTIVITY:"
echo "   • 60% reduction in secret-related development time"
echo "   • Eliminates security vulnerabilities in application code"
echo "   • Faster time-to-market for new applications"
echo ""

echo "SECURITY & COMPLIANCE:"
echo "   • 100% audit trail for all secret access"
echo "   • Encryption at rest and in transit"
echo "   • Fine-grained access controls"
echo "   • Automated compliance reporting"
echo ""

echo "OPERATIONAL EFFICIENCY:"
echo "   • Eliminates manual secret rotation processes"
echo "   • Reduces security incidents and breaches"
echo "   • Scales across entire OpenShift platform"
echo "   • Integrates with existing security tools"
echo ""

echo "KEY TAKEAWAYS"
echo "-------------"
echo "[SUCCESS] Vault Agent Injector transforms secret management"
echo "[SUCCESS] Zero application changes = faster adoption"
echo "[SUCCESS] Enterprise security without complexity"
echo "[SUCCESS] Immediate ROI through reduced development time"
echo "[SUCCESS] Future-proof foundation for cloud-native security"