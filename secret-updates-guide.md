# Enhanced Application with Faster Secret Updates

## Updated Deployment with Custom Vault Agent Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-agent-config
  namespace: default
data:
  vault-agent.hcl: |
    vault {
      address = "https://vault.vault.svc.cluster.local:8200"
      ca_cert = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
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
      # Restart command when secrets change
      command     = "pkill -HUP myapp || echo 'Process not found'"
      # Fast update interval
      wait        = "2s:10s"
    }
  
  config.txt.tpl: |
    {{- with secret "secret/data/myapp/config" -}}
    username={{ .Data.data.username }}
    password={{ .Data.data.password }}
    api_key={{ .Data.data.api_key }}
    # Updated at: {{ now | date "2006-01-02 15:04:05" }}
    {{- end -}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-enhanced
  namespace: default
  labels:
    app: myapp-enhanced
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp-enhanced
  template:
    metadata:
      labels:
        app: myapp-enhanced
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-configmap: "vault-agent-config"
        vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/myapp/config"
        vault.hashicorp.com/agent-inject-template-config.txt: |
          {{- with secret "secret/data/myapp/config" -}}
          username={{ .Data.data.username }}
          password={{ .Data.data.password }}
          api_key={{ .Data.data.api_key }}
          # Updated at: {{ now | date "2006-01-02 15:04:05" }}
          {{- end -}}
        # Enable template server for faster updates
        vault.hashicorp.com/template-static-secret-render-interval: "10s"
    spec:
      serviceAccountName: myapp
      containers:
      - name: myapp
        image: nginx:latest
        ports:
        - containerPort: 80
        # Add a simple script to reload on secret changes
        command:
        - /bin/sh
        - -c
        - |
          # Start nginx in background
          nginx -g 'daemon off;' &
          NGINX_PID=$!
          
          # Monitor secret file for changes
          echo "Monitoring /vault/secrets/config.txt for changes..."
          LAST_CHANGE=$(stat -c %Y /vault/secrets/config.txt 2>/dev/null || echo 0)
          
          while true; do
            sleep 5
            CURRENT_CHANGE=$(stat -c %Y /vault/secrets/config.txt 2>/dev/null || echo 0)
            if [ "$CURRENT_CHANGE" != "$LAST_CHANGE" ]; then
              echo "Secret file changed! Reloading configuration..."
              echo "New secrets:"
              cat /vault/secrets/config.txt
              LAST_CHANGE=$CURRENT_CHANGE
              # Here you would reload your actual application
              # kill -HUP $NGINX_PID
            fi
          done
```

### Method 4: Watch for Real-time Updates

Here's a script to monitor secret changes in real-time:

```bash
# monitor-secrets.sh
#!/bin/bash

POD_NAME=$(oc get pods -l app=myapp -n default -o jsonpath='{.items[0].metadata.name}')

echo "Monitoring secrets in pod: $POD_NAME"
echo "Initial secret values:"
oc exec $POD_NAME -c myapp -n default -- cat /vault/secrets/config.txt
echo "---"

# Monitor for changes every 5 seconds
while true; do
    sleep 5
    echo "Checking for updates at $(date)..."
    CURRENT_CONTENT=$(oc exec $POD_NAME -c myapp -n default -- cat /vault/secrets/config.txt 2>/dev/null)
    if [ "$CURRENT_CONTENT" != "$LAST_CONTENT" ]; then
        echo "🔄 SECRET UPDATED!"
        echo "$CURRENT_CONTENT"
        echo "---"
        LAST_CONTENT="$CURRENT_CONTENT"
    fi
done
```

## Immediate Test with Pod Restart

Let's test the update by restarting the pod to get the fresh secrets:

```bash
# Get current pod name
POD_NAME=$(oc get pods -l app=myapp -n default -o jsonpath='{.items[0].metadata.name}')

# Delete the pod to trigger recreation with updated secrets
oc delete pod $POD_NAME -n default

# Wait for new pod
oc wait --for=condition=Ready pod -l app=myapp -n default --timeout=60s

# Check updated secrets
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt
```

## Expected Results

After restarting the pod, you should see:
```
username=updateduser
password=newpassword123
api_key=xyz789updated
```

## Summary

**🔄 Secret Update Options:**

1. **Automatic (Slow)**: 30s-5min intervals (default)
2. **Pod Restart (Fast)**: Immediate update
3. **Enhanced Config (Medium)**: 10s intervals with file monitoring
4. **Custom Monitoring (Real-time)**: Application-level change detection

**💡 Best Practices:**
- Use **pod restarts** for immediate updates in development
- Configure **template intervals** for production automatic updates
- Implement **file watching** in applications for zero-downtime reloads
- Use **graceful reloads** (SIGHUP) instead of hard restarts

Would you like me to show you any of these methods in action?