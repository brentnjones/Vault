# Vault Agent Polling Interval Configuration

## How Polling Intervals Work

The Vault Agent polling interval is controlled by several factors:

### 1. **Default Behavior (What You're Seeing)**

By default, Vault Agent uses **Consul Template** under the hood, which has these intervals:

- **Initial fetch**: Immediate when starting
- **Re-fetch interval**: Based on secret lease duration
- **Minimum interval**: 30 seconds (default)
- **Maximum interval**: 5 minutes (default)

### 2. **Current Configuration Analysis**

From your pod configuration, I can see:

```json
{
  "template": [
    {
      "destination": "/vault/secrets/config.txt",
      "contents": "{{- with secret \"secret/data/myapp/config\" -}}...",
      "left_delimiter": "{{",
      "right_delimiter": "}}"
    }
  ]
}
```

**Missing configuration means defaults are used:**
- No `wait` parameter = uses default intervals
- No `error_on_missing_key` = continues on errors
- No custom retry logic = uses default backoff

### 3. **Checking Current Intervals**

To see the actual polling behavior:

```bash
# Check Vault Agent logs with timestamps
oc logs -l app=myapp -c vault-agent -n default --timestamps=true | grep rendered

# Monitor in real-time
oc logs -l app=myapp -c vault-agent -n default --follow --timestamps=true

# Check secret lease information
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq '.lease_duration'
```

### 4. **Factors That Determine Polling Frequency**

#### **A. Secret Lease Duration**
```bash
# Check the lease duration of your secret
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq '.lease_duration'

# Check Vault's default lease settings
oc exec vault-0 -n vault -- vault read sys/mounts/secret/tune
```

#### **B. Template Wait Configuration**
The `wait` parameter controls how often templates are evaluated:

```yaml
# Example with custom wait times
vault.hashicorp.com/agent-inject-template-config.txt: |
  {{- with secret "secret/data/myapp/config" -}}
  username={{ .Data.data.username }}
  password={{ .Data.data.password }}
  api_key={{ .Data.data.api_key }}
  {{- end -}}

# To add wait configuration, you'd need a custom ConfigMap:
vault.hashicorp.com/agent-configmap: "custom-vault-config"
```

#### **C. Token Renewal Intervals**
```bash
# Check token TTL and renewal
oc exec -l app=myapp -c vault-agent -n default -- cat /home/vault/.vault-token | \
  oc exec -i vault-0 -n vault -- vault token lookup -format=json - | jq '.data.ttl'
```

### 5. **How to Configure Custom Intervals**

#### **Method 1: Using Annotations (Limited)**

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "myapp"
  # This controls static secret render interval
  vault.hashicorp.com/template-static-secret-render-interval: "10s"
  vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/myapp/config"
  vault.hashicorp.com/agent-inject-template-config.txt: |
    {{- with secret "secret/data/myapp/config" -}}
    username={{ .Data.data.username }}
    password={{ .Data.data.password }}
    api_key={{ .Data.data.api_key }}
    {{- end -}}
```

#### **Method 2: Custom ConfigMap (Full Control)**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-vault-agent-config
data:
  config.hcl: |
    vault {
      address = "http://vault.vault.svc:8200"
    }
    
    auto_auth {
      method "kubernetes" {
        mount_path = "auth/kubernetes"
        config = {
          role = "myapp"
          token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        }
      }
    }
    
    template {
      source      = "/vault/templates/config.txt.tpl"
      destination = "/vault/secrets/config.txt"
      # Custom polling intervals
      wait = {
        min = "5s"     # Minimum wait between checks
        max = "30s"    # Maximum wait between checks
      }
      # Restart behavior
      command = "echo 'Secret updated at $(date)' >> /vault/secrets/update.log"
      # Error handling
      error_on_missing_key = false
      backup = true
    }
---
# Then reference it in your deployment:
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "myapp"
  vault.hashicorp.com/agent-configmap: "custom-vault-agent-config"
```

### 6. **Determining Your Current Interval**

Run this script to monitor your actual polling interval:

```bash
#!/bin/bash
# monitor-polling.sh

echo "Monitoring Vault Agent polling interval..."
echo "Watching for template renders..."

POD_NAME=$(oc get pods -l app=myapp -n default -o jsonpath='{.items[0].metadata.name}')

# Follow logs and extract render timestamps
oc logs $POD_NAME -c vault-agent -n default --follow --timestamps=true | \
  grep "rendered" | \
  while read line; do
    timestamp=$(echo $line | cut -d' ' -f1)
    echo "Template rendered at: $timestamp"
    if [ ! -z "$last_timestamp" ]; then
      # Calculate interval (requires date command with timestamp support)
      echo "  Time since last render: $(( $(date -d "$timestamp" +%s) - $(date -d "$last_timestamp" +%s) )) seconds"
    fi
    last_timestamp=$timestamp
  done
```

### 7. **Quick Test: Force a Render**

To see immediate polling behavior:

```bash
# Update a secret and watch logs
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="test$(date +%s)" \
    password="updated$(date +%s)" \
    api_key="$(date)"

# Watch for the update
oc logs -l app=myapp -c vault-agent -n default --follow --timestamps=true | grep rendered
```

### 8. **Understanding the Timeline**

Based on your experience:

1. **Secret updated in Vault**: ~21:17 (when you ran the kv put command)
2. **Template rendered**: ~21:20 (from the logs)
3. **Interval**: Approximately **3 minutes**

This suggests either:
- Default lease duration polling
- Consul Template's default max wait of 300s (5 minutes)
- Token renewal triggered the template refresh

### 9. **Production Recommendations**

#### **For Development:**
```yaml
vault.hashicorp.com/template-static-secret-render-interval: "10s"
```

#### **For Production:**
```yaml
# Use ConfigMap with wait configuration
wait = {
  min = "30s"    # Don't check too frequently
  max = "300s"   # But don't wait more than 5 minutes
}
```

#### **For High-Frequency Updates:**
```yaml
wait = {
  min = "5s"     # Quick response
  max = "30s"    # Reasonable maximum
}
```

### 10. **Verification Commands**

```bash
# Check current secret version and timing
oc exec vault-0 -n vault -- vault kv get -format=json secret/myapp/config | jq '.data.metadata'

# Monitor template renders in real-time
oc logs -l app=myapp -c vault-agent -n default --follow | grep -E "(rendered|template)"

# Check token renewal frequency
oc logs -l app=myapp -c vault-agent -n default | grep "renewed auth token"
```

The 3-minute interval you experienced is likely the default behavior based on token lease duration and Consul Template's built-in intervals.