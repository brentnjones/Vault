# Vault Agent Injector Demo Script

## 🎯 Demo Overview: Zero-Touch Secret Management in OpenShift

**What you'll demonstrate:**
- Automatic secret injection into applications
- Real-time secret updates without pod restarts
- Zero application code changes required
- Enterprise-grade security with audit trails

---

## 📋 Pre-Demo Checklist

### ✅ Environment Verification
```bash
# Verify Vault is running
oc get pods -n vault
oc get route vault -n vault

# Verify demo app is ready
oc get deployment myapp -n default
oc get pods -l app=myapp -n default

# Check current secrets
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
```

### 🎪 Demo Environment Status
- **Vault Server**: ✅ Running on OpenShift
- **Agent Injector**: ✅ Automatically injects secrets
- **Sample App**: ✅ nginx with secret injection
- **Update Interval**: ✅ 30 seconds for responsive demo

---

## 🎬 Demo Script: "From Manual to Automatic Secret Management"

### **Scene 1: The Problem (2 minutes)**

**Narration:** *"Traditional secret management requires developers to write custom code, manage tokens, and handle secret rotation manually."*

```bash
# Show traditional approach (conceptual)
echo "=== Traditional Secret Management Challenges ==="
echo "❌ Hardcoded secrets in application code"
echo "❌ Manual secret rotation processes"  
echo "❌ Security risks with exposed credentials"
echo "❌ Application restarts required for updates"
echo ""
```

### **Scene 2: The Vault Solution (3 minutes)**

**Narration:** *"With Vault Agent Injector, secrets are automatically delivered to applications with zero code changes."*

```bash
echo "=== Vault Agent Injector Architecture ==="
echo "✅ Vault Server: Centralized secret storage"
echo "✅ Agent Injector: Automatic secret delivery" 
echo "✅ Kubernetes Integration: Uses service accounts"
echo "✅ Zero Application Changes: Secrets appear as files"
echo ""

# Show the current setup
echo "=== Current Application Pods ==="
oc get pods -l app=myapp -n default -o wide

echo ""
echo "=== Pod Containers (Notice the Vault Containers) ==="
POD_NAME=$(oc get pods -l app=myapp -n default -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_NAME"
oc get pod $POD_NAME -n default -o jsonpath='{.spec.containers[*].name}' && echo
oc get pod $POD_NAME -n default -o jsonpath='{.spec.initContainers[*].name}' && echo
```

### **Scene 3: Current Secrets (1 minute)**

**Narration:** *"Let's see what secrets are currently available to our application."*

```bash
echo "=== Current Application Secrets ==="
echo "Application simply reads from /vault/secrets/config.txt:"
echo ""
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
echo ""
echo "No application code changes required - just read files!"
```

### **Scene 4: The Magic - Live Secret Update (5 minutes)**

**Narration:** *"Now watch as we update secrets in Vault and they automatically propagate to the application."*

```bash
echo "=== LIVE DEMO: Updating Secrets in Vault ==="
echo "Timestamp: $(date)"
echo ""

# Store current values for comparison
echo "Capturing current secret values..."
BEFORE_SECRETS=$(oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt 2>/dev/null)

echo "Current secrets:"
echo "$BEFORE_SECRETS"
echo ""

# Update secrets in Vault
echo "🔄 Updating secrets in Vault..."
DEMO_TIMESTAMP=$(date +%H%M%S)
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="live-demo-user-$DEMO_TIMESTAMP" \
    password="secure-password-$(date +%s)" \
    api_key="DEMO-KEY-$DEMO_TIMESTAMP"

echo ""
echo "✅ Secrets updated in Vault!"
echo "⏱️  Waiting for automatic propagation (max 30 seconds)..."
echo ""

# Monitor the update in real-time
for i in {1..40}; do
    CURRENT_SECRETS=$(oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt 2>/dev/null)
    
    if [ "$CURRENT_SECRETS" != "$BEFORE_SECRETS" ]; then
        echo "🎉 SUCCESS! Secrets automatically updated in $((i * 2)) seconds!"
        echo ""
        echo "=== New Application Secrets ==="
        echo "$CURRENT_SECRETS"
        echo ""
        echo "✨ No pod restart required!"
        echo "✨ No application downtime!"
        echo "✨ Zero code changes needed!"
        break
    fi
    
    echo -n "."
    sleep 2
done
echo ""
```

### **Scene 5: Security & Audit Trail (2 minutes)**

**Narration:** *"All secret access is logged and auditable through Vault."*

```bash
echo "=== Security & Compliance Benefits ==="
echo "✅ All secret access is audited"
echo "✅ Fine-grained access controls via policies"  
echo "✅ Automatic token rotation"
echo "✅ No secrets in container images"
echo ""

# Show Vault audit capabilities
echo "=== Vault Audit Information ==="
echo "Secret version and metadata:"
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq '.data.metadata'
echo ""

echo "Active policies:"
oc exec vault-0 -n vault -- vault policy read myapp-policy
```

### **Scene 6: Enterprise Benefits (2 minutes)**

**Narration:** *"This solution scales across your entire OpenShift environment."*

```bash
echo "=== Enterprise-Scale Benefits ==="
echo ""
echo "🏢 For Operations Teams:"
echo "   • Centralized secret management"
echo "   • Automated secret rotation"
echo "   • Complete audit trails"
echo "   • Policy-based access control"
echo ""
echo "👩‍💻 For Development Teams:"  
echo "   • Zero vault knowledge required"
echo "   • Secrets appear as simple files"
echo "   • Works with any programming language"
echo "   • No authentication code needed"
echo ""
echo "🔒 For Security Teams:"
echo "   • No secrets in source code"
echo "   • Encrypted at rest and in transit"
echo "   • Fine-grained access controls"
echo "   • Integration with existing security tools"
```

---

## 🎯 Demo Variations

### **Quick Demo (5 minutes)**
```bash
# Condensed version for time-constrained presentations
./quick-demo.sh
```

### **Technical Deep-dive (15 minutes)**
```bash
# Include architecture details and troubleshooting
./technical-demo.sh
```

### **Executive Summary (3 minutes)**
```bash
# Focus on business value and ROI
./executive-demo.sh
```

---

## 🛠 Demo Setup Commands

### **Reset Demo Environment**
```bash
# Reset to known state
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="demo-reset-user" \
    password="reset-password" \
    api_key="RESET-$(date +%H%M%S)"

# Wait for propagation
sleep 35

# Verify reset
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
```

### **Backup Demo State**
```bash
# Save current configuration
oc get deployment myapp -n default -o yaml > demo-backup.yaml
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config > demo-secrets-backup.json
```

### **Emergency Reset**
```bash
# If something goes wrong
oc rollout restart deployment myapp -n default
oc rollout status deployment myapp -n default
```

---

## 🎤 Speaker Notes

### **Key Talking Points:**
1. **Zero Application Changes**: Emphasize no code modifications needed
2. **Automatic Updates**: Highlight real-time secret propagation  
3. **Security First**: All secrets encrypted and audited
4. **Developer Friendly**: Simple file-based access pattern
5. **Enterprise Ready**: Scales across entire OpenShift platform

### **Common Questions & Answers:**

**Q: "What if Vault is down?"**
A: Applications continue running with last cached secrets. Vault Agent handles retries and recovery.

**Q: "How fast are updates?"**  
A: Configurable from seconds to minutes. Demo shows 30-second updates, production typically 2-5 minutes.

**Q: "Does this work with databases?"**
A: Yes! Vault supports dynamic database credentials with automatic rotation.

**Q: "What about secret rotation?"**
A: Fully automated. Vault can rotate secrets on schedule, applications get updates automatically.

**Q: "How does this compare to Kubernetes secrets?"**
A: Vault provides encryption at rest, audit trails, fine-grained policies, and automatic rotation - all missing from basic K8s secrets.

### **Demo Tips:**
- ✅ Test the full demo script beforehand
- ✅ Have the Web UI open for visual appeal
- ✅ Prepare backup slides if demo fails  
- ✅ Keep timing slides visible
- ✅ Practice the narrative flow

---

## 🚀 Extended Demo Ideas

### **Multi-Application Demo**
Show secrets being delivered to multiple different applications simultaneously.

### **Secret Rotation Demo**  
Demonstrate automatic database credential rotation.

### **Security Policy Demo**
Show how different applications get different secrets based on policies.

### **Disaster Recovery Demo**
Show Vault failover and application resilience.

---

## 📊 Success Metrics

After the demo, your audience should understand:
- ✅ How Vault Agent Injector eliminates secret management code
- ✅ The security benefits of centralized secret management  
- ✅ How automatic updates work without downtime
- ✅ The enterprise scalability of the solution
- ✅ The developer experience improvements

**Demo Duration: 15 minutes**  
**Technical Level: Intermediate**  
**Audience: DevOps, Security, Platform Engineers**