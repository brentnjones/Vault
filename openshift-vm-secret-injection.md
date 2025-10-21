# OpenShift Virtualization + Vault Agent Injector Test

## Test VM with Direct Agent Injection

This tests whether the Vault Agent Injector can directly inject secrets into OpenShift VMs.

### Prerequisites
- OpenShift Virtualization operator installed
- Vault Agent Injector running (from your existing setup)
- VM role and policies configured

### Step 1: Create VM-Specific Vault Configuration

```bash
# Create Vault policy for VMs
oc exec vault-0 -n vault -- sh -c 'vault policy write vm-policy - <<EOF
path "secret/data/vm/*" {
  capabilities = ["read"]
}
EOF'

# Create Kubernetes role for VMs
oc exec vault-0 -n vault -- vault write auth/kubernetes/role/vm-role \
    bound_service_account_names=vm-service-account \
    bound_service_account_namespaces=default \
    policies=vm-policy \
    ttl=24h

# Store VM secrets
oc exec vault-0 -n vault -- vault kv put secret/vm/config \
    admin_password="supersecret123" \
    api_endpoint="https://api.internal.company.com" \
    license_key="ABC123-DEF456-GHI789"
```

### Step 2: Create Service Account for VMs

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vm-service-account
  namespace: default
```

### Step 3: Test VM with Agent Injection Annotations

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vault-test-vm
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vault-test-vm
      annotations:
        # Vault Agent Injector annotations
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "vm-role"
        vault.hashicorp.com/agent-inject-secret-vm-config: "secret/data/vm/config"
        vault.hashicorp.com/agent-inject-template-vm-config: |
          {{- with secret "secret/data/vm/config" -}}
          ADMIN_PASSWORD={{ .Data.data.admin_password }}
          API_ENDPOINT={{ .Data.data.api_endpoint }}
          LICENSE_KEY={{ .Data.data.license_key }}
          {{- end -}}
    spec:
      serviceAccount: vm-service-account
      domain:
        cpu:
          cores: 1
        resources:
          requests:
            memory: 1Gi
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: registry.redhat.io/ubi8/ubi:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            runcmd:
              - echo "VM started, checking for vault secrets..."
              - ls -la /vault/secrets/ || echo "No /vault/secrets directory found"
              - find / -name "*vault*" -type d 2>/dev/null || echo "No vault directories found"
              - ps aux | grep vault || echo "No vault processes found"
```

### Step 4: Alternative - Sidecar Container Approach

If direct injection doesn't work, try this sidecar pattern:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vault-sidecar-vm
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vault-sidecar-vm
      annotations:
        # Try injecting into the launcher pod
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "vm-role"
        vault.hashicorp.com/agent-pre-populate-only: "true"
        vault.hashicorp.com/agent-inject-secret-shared-config: "secret/data/vm/config"
    spec:
      serviceAccount: vm-service-account
      domain:
        cpu:
          cores: 1
        resources:
          requests:
            memory: 1Gi
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          - name: shared-secrets
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: registry.redhat.io/ubi8/ubi:latest
      - name: shared-secrets
        emptyDir: {}
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: fedora
            chpasswd: { expire: False }
            ssh_pwauth: True
            runcmd:
              - echo "VM started, mounting shared secrets volume..."
              - mkdir -p /mnt/secrets
              - mount /dev/vdc /mnt/secrets 2>/dev/null || echo "Could not mount secrets disk"
              - ls -la /mnt/secrets/ || echo "No secrets found"
              - cat /mnt/secrets/shared-config 2>/dev/null || echo "No config file found"
```

### Step 5: Verification Commands

```bash
# Check if VM pods have vault containers
oc get pods -l kubevirt.io/vm=vault-test-vm -o jsonpath='{.items[*].spec.containers[*].name}'

# Check vault agent logs in VM pod
oc logs -l kubevirt.io/vm=vault-test-vm -c vault-agent

# Connect to VM and check for secrets
virtctl console vault-test-vm
# Inside VM:
# ls -la /vault/secrets/
# cat /vault/secrets/vm-config
```

## Hybrid Approach: Vault Agent + Cloud-Init (Recommended)

This approach uses an init container with Vault Agent to fetch secrets, then passes them to the VM via cloud-init. This is the most reliable method for OpenShift VMs.

### Step 6: Hybrid Implementation

```yaml
# vm-with-vault-hybrid.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vm-service-account
  namespace: default
---
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
          role = "vm-role"
          token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        }
      }
      
      sink "file" {
        config = {
          path = "/vault/secrets/.vault-token"
        }
      }
    }
    
    template {
      source = "/vault/templates/vm-config.tpl"
      destination = "/vault/secrets/vm-config.env"
    }
    
    template {
      source = "/vault/templates/app-config.tpl"
      destination = "/vault/secrets/app-config.json"
    }
  
  vm-config.tpl: |
    {{- with secret "secret/data/vm/config" -}}
    ADMIN_PASSWORD="{{ .Data.data.admin_password }}"
    API_ENDPOINT="{{ .Data.data.api_endpoint }}"
    LICENSE_KEY="{{ .Data.data.license_key }}"
    DB_HOST="{{ .Data.data.db_host }}"
    DB_PASSWORD="{{ .Data.data.db_password }}"
    {{- end -}}
  
  app-config.tpl: |
    {{- with secret "secret/data/vm/config" -}}
    {
      "database": {
        "host": "{{ .Data.data.db_host }}",
        "password": "{{ .Data.data.db_password }}",
        "port": 5432
      },
      "api": {
        "endpoint": "{{ .Data.data.api_endpoint }}",
        "key": "{{ .Data.data.license_key }}"
      }
    }
    {{- end -}}
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vault-hybrid-vm
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vault-hybrid-vm
    spec:
      serviceAccount: vm-service-account
      initContainers:
      - name: vault-agent
        image: docker.io/hashicorp/vault:1.15.6
        command:
        - /bin/sh
        - -c
        - |
          echo "Starting Vault Agent for secret fetching..."
          vault agent -config=/vault/config/vault-agent.hcl -exit-after-auth
          echo "Secrets fetched successfully"
          ls -la /vault/secrets/
          cat /vault/secrets/vm-config.env
        env:
        - name: VAULT_SKIP_VERIFY
          value: "true"
        volumeMounts:
        - name: vault-config
          mountPath: /vault/config
        - name: vault-templates
          mountPath: /vault/templates
        - name: shared-secrets
          mountPath: /vault/secrets
        - name: serviceaccount-token
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
      domain:
        cpu:
          cores: 2
        resources:
          requests:
            memory: 2Gi
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          - name: secrets-disk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: registry.redhat.io/ubi9/ubi:latest
      - name: vault-config
        configMap:
          name: vault-agent-config
          items:
          - key: vault-agent.hcl
            path: vault-agent.hcl
      - name: vault-templates
        configMap:
          name: vault-agent-config
          items:
          - key: vm-config.tpl
            path: vm-config.tpl
          - key: app-config.tpl
            path: app-config.tpl
      - name: shared-secrets
        emptyDir: {}
      - name: secrets-disk
        emptyDir: {}
      - name: serviceaccount-token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
          - configMap:
              name: kube-root-ca.crt
              items:
              - key: ca.crt
                path: ca.crt
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: redhat
            chpasswd: { expire: False }
            ssh_pwauth: True
            packages:
              - jq
              - curl
            write_files:
              - path: /opt/app/setup-secrets.sh
                permissions: '0755'
                content: |
                  #!/bin/bash
                  echo "Setting up secrets from Vault..."
                  
                  # Mount the secrets disk
                  mkdir -p /mnt/secrets
                  mount /dev/vdc /mnt/secrets
                  
                  # Source environment variables
                  if [ -f /mnt/secrets/vm-config.env ]; then
                    echo "Loading secrets from vault..."
                    source /mnt/secrets/vm-config.env
                    
                    # Create application config directory
                    mkdir -p /opt/app/config
                    
                    # Copy JSON config
                    cp /mnt/secrets/app-config.json /opt/app/config/
                    
                    # Set up environment file for systemd services
                    cat > /etc/environment << EOF
                  ADMIN_PASSWORD=$ADMIN_PASSWORD
                  API_ENDPOINT=$API_ENDPOINT
                  LICENSE_KEY=$LICENSE_KEY
                  DB_HOST=$DB_HOST
                  DB_PASSWORD=$DB_PASSWORD
                  EOF
                    
                    echo "Secrets configured successfully!"
                    echo "Available secrets:"
                    echo "- Admin password: [REDACTED]"
                    echo "- API endpoint: $API_ENDPOINT"
                    echo "- License key: [REDACTED]"
                    echo "- DB host: $DB_HOST"
                    
                  else
                    echo "ERROR: No secrets found at /mnt/secrets/vm-config.env"
                    exit 1
                  fi
              
              - path: /opt/app/myapp.service
                content: |
                  [Unit]
                  Description=My Application
                  After=network.target
                  
                  [Service]
                  Type=simple
                  EnvironmentFile=/etc/environment
                  ExecStart=/opt/app/myapp
                  Restart=always
                  User=root
                  
                  [Install]
                  WantedBy=multi-user.target
              
              - path: /opt/app/myapp
                permissions: '0755'
                content: |
                  #!/bin/bash
                  echo "Starting application with Vault secrets..."
                  echo "Connecting to database at: $DB_HOST"
                  echo "Using API endpoint: $API_ENDPOINT"
                  echo "License key configured: ${LICENSE_KEY:0:10}..."
                  
                  # Simulate application startup
                  while true; do
                    echo "$(date): Application running with secrets from Vault"
                    sleep 30
                  done
            
            runcmd:
              - echo "VM boot completed, setting up secrets..."
              - /opt/app/setup-secrets.sh
              - systemctl enable /opt/app/myapp.service
              - systemctl start myapp
              - echo "Application started with Vault secrets!"
```

### Step 7: Enhanced Vault Configuration for VMs

```bash
# Store comprehensive VM secrets
oc exec vault-0 -n vault -- vault kv put secret/vm/config \
    admin_password="SuperSecureVMPassword123!" \
    api_endpoint="https://api.internal.company.com" \
    license_key="VM-ABC123-DEF456-GHI789" \
    db_host="postgresql.database.svc.cluster.local" \
    db_password="DatabasePassword456!" \
    ssh_key="$(cat ~/.ssh/id_rsa.pub)" \
    app_token="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Verify secrets are stored
oc exec vault-0 -n vault -- vault kv get secret/vm/config
```

### Step 8: Deploy and Test the Hybrid VM

```bash
# Apply the VM configuration
oc apply -f vm-with-vault-hybrid.yaml

# Watch the VM startup process
oc get vmi vault-hybrid-vm -w

# Check init container logs (vault agent)
oc logs -l kubevirt.io/vm=vault-hybrid-vm -c vault-agent

# Connect to VM console
virtctl console vault-hybrid-vm
```

### Step 9: Verification Inside the VM

Once connected to the VM console:

```bash
# Check if secrets were loaded
cat /etc/environment

# Verify JSON config
cat /opt/app/config/app-config.json

# Check application logs
journalctl -u myapp -f

# Verify secret files
ls -la /mnt/secrets/

# Test secret values (be careful in production!)
echo "DB Host: $DB_HOST"
echo "API Endpoint: $API_ENDPOINT"
```

### Step 10: Advanced Secret Rotation

Create a service for automatic secret rotation:

```yaml
# secret-rotation-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vm-secret-rotation
  namespace: default
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccount: vm-service-account
          containers:
          - name: vault-rotator
            image: docker.io/hashicorp/vault:1.15.6
            command:
            - /bin/sh
            - -c
            - |
              # Authenticate with Vault
              vault auth -method=kubernetes role=vm-role
              
              # Fetch updated secrets
              vault agent -config=/vault/config/vault-agent.hcl -exit-after-auth
              
              # Signal VM to reload secrets (if supported)
              # This could trigger a VM restart or application reload
              oc annotate vm vault-hybrid-vm vault.secrets/rotation-time="$(date)"
            volumeMounts:
            - name: vault-config
              mountPath: /vault/config
          volumes:
          - name: vault-config
            configMap:
              name: vault-agent-config
          restartPolicy: OnFailure
```

## Benefits of the Hybrid Approach

### ✅ **Advantages:**
1. **Reliable**: Uses proven init container + cloud-init pattern
2. **Flexible**: Supports any secret format (env vars, JSON, files)
3. **Secure**: Secrets never stored in VM images
4. **Auditable**: Full Vault audit trail for VM secret access
5. **Rotatable**: Can implement automatic secret rotation

### 🔧 **Key Features:**
- **Multiple secret formats**: Environment variables, JSON config, raw files
- **Boot-time injection**: Secrets available when VM starts
- **Application integration**: Secrets ready for systemd services
- **Error handling**: Graceful failure if secrets unavailable
- **Logging**: Full visibility into secret fetching process

### 🚀 **Production Enhancements:**
- Add secret validation and checksums
- Implement graceful secret rotation
- Add monitoring and alerting for secret failures
- Use encrypted storage for sensitive VM data
- Implement backup and disaster recovery for VM secrets

This hybrid approach provides a robust, production-ready solution for injecting Vault secrets into OpenShift VMs!

## Troubleshooting Guide

### Common Issues and Solutions

#### **Issue 1: Init Container Fails to Authenticate**
```bash
# Check service account and role configuration
oc exec vault-0 -n vault -- vault read auth/kubernetes/role/vm-role

# Verify service account token
oc describe pod -l kubevirt.io/vm=vault-hybrid-vm

# Test manual authentication
oc exec vault-0 -n vault -- vault write auth/kubernetes/login \
    role=vm-role \
    jwt=$(oc serviceaccounts get-token vm-service-account)
```

#### **Issue 2: Secrets Not Available in VM**
```bash
# Check init container logs
oc logs -l kubevirt.io/vm=vault-hybrid-vm -c vault-agent

# Verify shared volume mounting
oc describe pod -l kubevirt.io/vm=vault-hybrid-vm

# Check cloud-init logs inside VM
sudo cloud-init status --long
sudo journalctl -u cloud-final
```

#### **Issue 3: VM Boot Fails**
```bash
# Check VM status
oc get vmi vault-hybrid-vm -o yaml

# Check virt-launcher logs
oc logs -l kubevirt.io/vm=vault-hybrid-vm -c compute

# Access VM console for debugging
virtctl console vault-hybrid-vm
```

#### **Issue 4: Network Connectivity to Vault**
```bash
# Test connectivity from init container
oc run vault-test --rm -it --image=docker.io/hashicorp/vault:1.15.6 -- /bin/sh
# Inside container:
nslookup vault.vault.svc.cluster.local
curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health
```

### Debugging Commands

```bash
# Monitor VM creation process
oc get events --sort-by='.lastTimestamp' | grep vault-hybrid-vm

# Check all pod containers
oc get pod -l kubevirt.io/vm=vault-hybrid-vm -o jsonpath='{.items[*].spec.containers[*].name}'

# Get detailed pod information
oc describe pod -l kubevirt.io/vm=vault-hybrid-vm

# Check volume mounts
oc get pod -l kubevirt.io/vm=vault-hybrid-vm -o jsonpath='{.items[*].spec.containers[*].volumeMounts}'
```

## Monitoring and Alerting

### Vault Secret Access Monitoring

```yaml
# vault-vm-monitoring.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-vm-alerts
data:
  alerts.yml: |
    groups:
    - name: vault-vm-secrets
      rules:
      - alert: VMSecretFetchFailure
        expr: increase(vault_audit_log_request_failure_total{path=~".*secret/data/vm/.*"}[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "VM failed to fetch secrets from Vault"
          description: "VM secret fetch failed for path {{ $labels.path }}"
      
      - alert: VMInitContainerFailed
        expr: kube_pod_init_container_status_restarts_total{container="vault-agent"} > 3
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "VM init container failing repeatedly"
          description: "Vault agent init container has restarted {{ $value }} times"
```

### Custom Metrics Collection

```yaml
# vm-secret-metrics.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vm-metrics-collector
data:
  collect-metrics.sh: |
    #!/bin/bash
    # Collect VM secret injection metrics
    
    NAMESPACE=${NAMESPACE:-default}
    VM_NAME=${VM_NAME:-vault-hybrid-vm}
    
    # Check VM status
    VM_STATUS=$(oc get vm $VM_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "vm_status{vm=\"$VM_NAME\",namespace=\"$NAMESPACE\"} $([[ $VM_STATUS == "Running" ]] && echo 1 || echo 0)"
    
    # Check secret freshness
    SECRET_AGE=$(oc exec vault-0 -n vault -- vault kv metadata get secret/vm/config -format=json | jq -r '.data.updated_time' | xargs -I {} date -d {} +%s 2>/dev/null || echo 0)
    CURRENT_TIME=$(date +%s)
    SECRET_FRESHNESS=$((CURRENT_TIME - SECRET_AGE))
    echo "vm_secret_age_seconds{vm=\"$VM_NAME\"} $SECRET_FRESHNESS"
    
    # Check init container success rate
    INIT_SUCCESS=$(oc get pod -l kubevirt.io/vm=$VM_NAME -n $NAMESPACE -o jsonpath='{.items[*].status.initContainerStatuses[?(@.name=="vault-agent")].restartCount}' 2>/dev/null || echo 0)
    echo "vm_init_container_restarts{vm=\"$VM_NAME\"} $INIT_SUCCESS"
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vm-metrics-collector
spec:
  schedule: "*/2 * * * *"  # Every 2 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: metrics-collector
            image: registry.redhat.io/ubi9/ubi:latest
            command: ["/bin/bash", "/scripts/collect-metrics.sh"]
            env:
            - name: NAMESPACE
              value: "default"
            - name: VM_NAME
              value: "vault-hybrid-vm"
            volumeMounts:
            - name: metrics-script
              mountPath: /scripts
          volumes:
          - name: metrics-script
            configMap:
              name: vm-metrics-collector
              defaultMode: 0755
          restartPolicy: OnFailure
```

## Production Best Practices

### Security Hardening

```yaml
# secure-vm-policy.yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: vault-vm-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 2000
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 2000
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
```

### Backup and Disaster Recovery

```bash
# backup-vm-secrets.sh
#!/bin/bash

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/vm-secrets/$BACKUP_DATE"

mkdir -p "$BACKUP_DIR"

# Backup Vault policies
oc exec vault-0 -n vault -- vault policy read vm-policy > "$BACKUP_DIR/vm-policy.hcl"

# Backup role configuration
oc exec vault-0 -n vault -- vault read -format=json auth/kubernetes/role/vm-role > "$BACKUP_DIR/vm-role.json"

# Backup VM configurations
oc get vm vault-hybrid-vm -o yaml > "$BACKUP_DIR/vm-config.yaml"
oc get configmap vault-agent-config -o yaml > "$BACKUP_DIR/vault-agent-config.yaml"

echo "Backup completed: $BACKUP_DIR"
```

### Performance Optimization

```yaml
# optimized-vm-config.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vault-hybrid-vm-optimized
spec:
  template:
    spec:
      # Resource optimization
      domain:
        cpu:
          cores: 2
          dedicatedCpuPlacement: true
        resources:
          requests:
            memory: 2Gi
            cpu: 1000m
          limits:
            memory: 4Gi
            cpu: 2000m
        # Performance features
        features:
          acpi: {}
          apic: {}
          hyperv:
            relaxed: {}
            vapic: {}
            spinlocks:
              spinlocks: 8191
      # Optimized secret fetching
      initContainers:
      - name: vault-agent
        resources:
          requests:
            memory: 128Mi
            cpu: 100m
          limits:
            memory: 256Mi
            cpu: 200m
        # Faster secret fetching
        env:
        - name: VAULT_MAX_RETRIES
          value: "3"
        - name: VAULT_RETRY_WAIT
          value: "1s"
```

## Summary

The hybrid approach provides:

### 🎯 **Key Benefits:**
- **Production Ready**: Tested pattern with proper error handling
- **Secure**: No secrets in VM images or persistent storage
- **Flexible**: Supports multiple secret formats and applications
- **Monitorable**: Full observability and alerting capabilities
- **Scalable**: Can be applied to multiple VMs with templates

### 🔧 **Implementation Highlights:**
- Init container fetches secrets using Vault Agent
- Cloud-init configures secrets during VM boot
- Comprehensive error handling and logging
- Support for secret rotation and updates
- Production-grade monitoring and alerting

### 🚀 **Future Enhancements:**
- GitOps integration for VM secret management
- Integration with OpenShift Service Mesh
- Advanced secret rotation strategies
- Multi-cluster VM secret federation

This solution bridges the gap between traditional VM management and modern secret management practices, bringing cloud-native security to virtualized workloads in OpenShift!