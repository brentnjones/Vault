# Vault Agent Injector Setup Guide for OpenShift

This guide provides a complete step-by-step setup for Vault Agent Injector in OpenShift environments.

## Prerequisites

- OpenShift 4.x cluster
- `oc` CLI configured and logged in
- Helm 3.x installed
- Cluster admin role or sufficient permissions to:
  - Create projects/namespaces
  - Create SecurityContextConstraints (SCCs)
  - Deploy workloads with specific security contexts

## Important OpenShift-Specific Considerations

### Container Registry Configuration
OpenShift defaults to the Red Hat registry (`registry.connect.redhat.com`) for container images. To ensure successful deployment, this guide explicitly specifies `docker.io` registry for all Vault components:

- **Vault Server**: Uses `docker.io/hashicorp/vault:1.15.6`
- **Vault Agent Injector**: Uses `docker.io/hashicorp/vault-k8s:1.3.1`
- **Vault Agent**: Uses `docker.io/hashicorp/vault:1.15.6` (configured via `injector.agentImage`)

### Single-Node Cluster Considerations
For single-node OpenShift clusters (such as CodeReady Containers):

- Set `injector.replicas=1` to avoid pod anti-affinity issues
- Use standalone Vault configuration instead of HA mode
- Ensure sufficient resources are available for all components

### SecurityContextConstraints (SCCs)
Vault requires specific capabilities and security contexts that differ from OpenShift's default security policies. This guide creates a custom SCC with the necessary permissions.

## Deployment Planning

### Choosing Between Multi-Node and Single-Node Deployment

**Multi-Node (HA) Deployment - Recommended for:**
- Production environments
- Environments requiring high availability
- Clusters with 3+ worker nodes
- When fault tolerance is critical

**Single-Node (Standalone) Deployment - Suitable for:**
- Development and testing environments
- Single-node OpenShift clusters (e.g., CodeReady Containers)
- Resource-constrained environments
- Proof of concept deployments

**How to check your cluster configuration:**
```bash
# Check number of worker nodes
oc get nodes --show-labels | grep worker

# Check if you have multiple schedulable nodes
oc get nodes | grep -v master | grep Ready
```

## Step 1: Add HashiCorp Helm Repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

## Step 2: Choose Your Deployment Strategy

### Option A: Full Vault Deployment (Recommended for Dev/Test)

First, create the project and set up security context constraints:

```bash
# Create project
oc new-project vault

# Create custom SCC for Vault
oc apply -f - <<EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: vault-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: ["IPC_LOCK"]
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities: null
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

# Create service accounts with proper Helm labels
oc apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-server
  namespace: vault
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: vault
    app.kubernetes.io/instance: vault
  annotations:
    meta.helm.sh/release-name: vault
    meta.helm.sh/release-namespace: vault
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-agent-injector
  namespace: vault
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: vault-agent-injector
    app.kubernetes.io/instance: vault
  annotations:
    meta.helm.sh/release-name: vault
    meta.helm.sh/release-namespace: vault
EOF

# Bind service accounts to SCC
oc adm policy add-scc-to-user vault-scc -z vault-server -n vault
oc adm policy add-scc-to-user vault-scc -z vault-agent-injector -n vault

# Install Vault with OpenShift-specific settings

## For Multi-Node Clusters (HA Configuration):

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.image.repository=docker.io/hashicorp/vault" \
  --set "server.image.tag=1.15.6" \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true" \
  --set "server.ha.replicas=3" \
  --set "server.serviceAccount.create=false" \
  --set "server.serviceAccount.name=vault-server" \
  --set "server.resources.requests.memory=512Mi" \
  --set "server.resources.requests.cpu=250m" \
  --set "server.resources.limits.memory=1Gi" \
  --set "server.resources.limits.cpu=500m" \
  --set "server.route.enabled=true" \
  --set "server.route.host=vault-$(oc project -q).apps.$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')" \
  --set "ui.enabled=true" \
  --set "injector.enabled=true" \
  --set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
  --set "injector.image.tag=1.3.1" \
  --set "injector.agentImage.repository=docker.io/hashicorp/vault" \
  --set "injector.agentImage.tag=1.15.6" \
  --set "injector.serviceAccount.create=false" \
  --set "injector.serviceAccount.name=vault-agent-injector" \
  --set "injector.replicas=2" \
  --set "injector.resources.requests.memory=256Mi" \
  --set "injector.resources.requests.cpu=250m" \
  --set "injector.resources.limits.memory=512Mi" \
  --set "injector.resources.limits.cpu=250m"
```

## For Single-Node Clusters (Standalone Configuration):

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.image.repository=docker.io/hashicorp/vault" \
  --set "server.image.tag=1.15.6" \
  --set "server.standalone.enabled=true" \
  --set "server.serviceAccount.create=false" \
  --set "server.serviceAccount.name=vault-server" \
  --set "server.resources.requests.memory=512Mi" \
  --set "server.resources.requests.cpu=250m" \
  --set "server.resources.limits.memory=1Gi" \
  --set "server.resources.limits.cpu=500m" \
  --set "server.route.enabled=true" \
  --set "server.route.host=vault-$(oc project -q).apps.$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')" \
  --set "ui.enabled=true" \
  --set "injector.enabled=true" \
  --set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
  --set "injector.image.tag=1.3.1" \
  --set "injector.agentImage.repository=docker.io/hashicorp/vault" \
  --set "injector.agentImage.tag=1.15.6" \
  --set "injector.serviceAccount.create=false" \
  --set "injector.serviceAccount.name=vault-agent-injector" \
  --set "injector.replicas=1" \
  --set "injector.resources.requests.memory=256Mi" \
  --set "injector.resources.requests.cpu=250m" \
  --set "injector.resources.limits.memory=512Mi" \
  --set "injector.resources.limits.cpu=250m"
```

### Key Differences:

**Multi-Node (HA):**
- Uses `server.ha.enabled=true` with 3 replicas
- Provides high availability and fault tolerance
- Requires pod anti-affinity (pods spread across nodes)
- Recommended for production environments

**Single-Node (Standalone):**
- Uses `server.standalone.enabled=true` with 1 replica
- Single point of failure but simpler setup
- No anti-affinity constraints
- Suitable for development, testing, or resource-constrained environments
```

### Option B: Injector-Only Deployment (For External Vault)

If you have an external Vault cluster, you can install only the injector:

```bash
# Create project
oc new-project vault

# Create service account for injector
oc create serviceaccount vault-agent-injector -n vault

# Create and apply SCC
oc apply -f - <<EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: vault-injector-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities: null
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

# Bind service account to SCC
oc adm policy add-scc-to-user vault-injector-scc -z vault-agent-injector -n vault

# Install injector only
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.enabled=false" \
  --set "injector.enabled=true" \
  --set "injector.serviceAccount.create=false" \
  --set "injector.serviceAccount.name=vault-agent-injector" \
  --set "injector.externalVaultAddr=https://your-external-vault.example.com:8200" \
  --set "injector.replicas=2"
```

## Step 3: Verify Installation

Check that all components are running:

```bash
oc get pods -n vault
oc get services -n vault
oc get routes -n vault  # Check OpenShift routes for UI access
```

Expected output should show:
- Vault server pods (if using Option A)
- Vault agent injector pods
- Services for Vault UI and API
- OpenShift routes for external access (if configured)

### Fix Route TLS Termination (Important)

The default Vault route uses `passthrough` TLS termination, but Vault serves HTTP internally. For the Web UI to work properly, update the route to use `edge` termination:

```bash
# Fix route TLS termination for Web UI access
oc patch route vault -n vault -p '{"spec":{"tls":{"termination":"edge","insecureEdgeTerminationPolicy":"Redirect"}}}'

# Verify the route is now configured correctly
oc get route vault -n vault
```

The route should now show `edge/Redirect` in the TERMINATION column. You can now access the Vault Web UI at the route URL in your browser.

### Fix Route Visibility in Topology View (Optional)

If the route doesn't appear connected to Vault in the OpenShift topology view, add these labels and annotations:

```bash
# Add topology grouping labels
oc label route vault -n vault app.kubernetes.io/part-of=vault app=vault app.openshift.io/runtime=vault
oc label statefulset vault -n vault app.kubernetes.io/part-of=vault app=vault
oc label service vault-active -n vault app.kubernetes.io/part-of=vault app=vault

# Add topology connection annotations
oc annotate route vault -n vault app.openshift.io/connects-to='[{"apiVersion":"apps/v1","kind":"StatefulSet","name":"vault"}]'
oc annotate route vault -n vault app.openshift.io/vcs-uri="vault-cluster"
oc annotate route vault -n vault app.openshift.io/runtime-namespace=vault
```

## Step 4: Initialize and Unseal Vault (Option A only)

If you deployed the full Vault server, initialize and unseal it:

### For Multi-Node (HA) Deployment:

**Important:** The HA deployment requires proper Raft storage configuration. If you encounter Consul connection errors, ensure the Helm installation includes `--set "server.ha.raft.enabled=true"`.

```bash
# Initialize Vault (using standard 5 keys with 3 threshold for security)
oc exec vault-0 -n vault -- vault operator init -key-shares=5 -key-threshold=3 -format=json > cluster-keys.json

# Extract root token for verification
VAULT_ROOT_TOKEN=$(cat cluster-keys.json | jq -r ".root_token")
echo "Root Token: $VAULT_ROOT_TOKEN"

# Unseal vault-0 (leader) with 3 keys
oc exec vault-0 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[0]')"
oc exec vault-0 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[1]')"
oc exec vault-0 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[2]')"

# Have vault-1 and vault-2 join the Raft cluster
oc exec vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
oc exec vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200

# Unseal vault-1 with 3 keys
oc exec vault-1 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[0]')"
oc exec vault-1 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[1]')"
oc exec vault-1 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[2]')"

# Unseal vault-2 with 3 keys
oc exec vault-2 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[0]')"
oc exec vault-2 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[1]')"
oc exec vault-2 -n vault -- vault operator unseal "$(cat cluster-keys.json | jq -r '.unseal_keys_b64[2]')"

# Verify cluster status
oc exec vault-0 -n vault -- vault login "$VAULT_ROOT_TOKEN"
oc exec vault-0 -n vault -- vault operator raft list-peers
```

### For Single-Node (Standalone) Deployment:

```bash
# Initialize Vault
oc exec vault-0 -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json

# Extract unseal key and root token
VAULT_UNSEAL_KEY=$(cat cluster-keys.json | jq -r ".unseal_keys_b64[]")
VAULT_ROOT_TOKEN=$(cat cluster-keys.json | jq -r ".root_token")

# Display the values for verification
echo "Unseal Key: $VAULT_UNSEAL_KEY"
echo "Root Token: $VAULT_ROOT_TOKEN"

# Unseal the single Vault instance
oc exec vault-0 -n vault -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

**Important:** Save the `cluster-keys.json` file securely as it contains the unseal keys and root token needed to access Vault.

## Step 5: Configure Kubernetes Authentication

Set up Kubernetes auth method for the injector:

```bash
# Login to Vault using the root token
oc exec vault-0 -n vault -- vault login "$VAULT_ROOT_TOKEN"

# Enable Kubernetes auth method
oc exec vault-0 -n vault -- vault auth enable kubernetes

# Configure Kubernetes auth method
oc exec vault-0 -n vault -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443"
```

Alternative method using port forwarding:

```bash
# Port forward to access Vault locally
oc port-forward service/vault 8200:8200 -n vault &

# Set environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$VAULT_ROOT_TOKEN"

# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

For service account method:

```bash
# Create service account for Vault
oc create serviceaccount vault-auth -n vault

# Create ClusterRoleBinding
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: vault
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: vault
EOF

# Get the service account token
SECRET_NAME=$(oc get serviceaccount vault-auth -n vault -o jsonpath='{.secrets[0].name}')
TR_ACCOUNT_TOKEN=$(oc get secret $SECRET_NAME -n vault -o jsonpath='{.data.token}' | base64 --decode)

# Configure Kubernetes auth with service account
vault write auth/kubernetes/config \
    token_reviewer_jwt="$TR_ACCOUNT_TOKEN" \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

## Step 6: Create Vault Policies and Roles

Create a policy for your application:

```bash
# Method 1: Using shell command in pod (recommended)
oc exec vault-0 -n vault -- sh -c 'vault policy write myapp-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF'

# Method 2: Create policy file and apply it
cat <<EOF > myapp-policy.hcl
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

oc cp myapp-policy.hcl vault/vault-0:/tmp/myapp-policy.hcl
oc exec vault-0 -n vault -- vault policy write myapp-policy /tmp/myapp-policy.hcl
```

Create a Kubernetes role:

```bash
# Create Kubernetes role  
oc exec vault-0 -n vault -- vault write auth/kubernetes/role/myapp \
    bound_service_account_names=myapp \
    bound_service_account_namespaces=default \
    policies=myapp-policy \
    ttl=24h
```

## Step 7: Store Secrets in Vault

Create some test secrets:

```bash
# Enable KV v2 secrets engine
oc exec vault-0 -n vault -- vault secrets enable -path=secret kv-v2

# Store a secret
oc exec vault-0 -n vault -- vault kv put secret/myapp/config \
    username="myuser" \
    password="mypassword" \
    api_key="abc123def456"

# Verify the secret was stored
oc exec vault-0 -n vault -- vault kv get secret/myapp/config
```

## Step 8: Create Application with Injector Annotations

Create a sample application that uses the injector:

```yaml
# myapp-deployment.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-inject-secret-config.txt: "secret/data/myapp/config"
        vault.hashicorp.com/agent-inject-template-config.txt: |
          {{- with secret "secret/data/myapp/config" -}}
          username={{ .Data.data.username }}
          password={{ .Data.data.password }}
          api_key={{ .Data.data.api_key }}
          {{ end }}
    spec:
      serviceAccountName: myapp
      containers:
      - name: myapp
        image: nginx:latest
        ports:
        - containerPort: 80
```

Deploy the application:

```bash
oc apply -f myapp-deployment.yaml
```

## Step 9: Verify Secret Injection

Check that secrets were injected:

```bash
# Check pods are running
oc get pods -l app=myapp -n default

# Exec into the pod and verify secrets
oc exec -it deployment/myapp -c myapp -n default -- cat /vault/secrets/config.txt

# or
oc exec -it myapp-cdd6b6bc4-cl6dl -n default -- cat /vault/secrets/config.txt
```

Expected output should show the rendered secrets:
```
username=myuser
password=mypassword
api_key=abc123def456
```

**Note**: If some secrets are missing from the output, verify:
1. The secrets exist in Vault: `oc exec vault-0 -n vault -- vault kv get secret/myapp/config`
2. The template syntax in annotations matches the secret field names
3. Check vault agent logs: `oc logs <pod-name> -c vault-agent`

## Advanced Configuration Options

### Custom Vault Agent Configuration

You can customize the Vault Agent configuration using annotations:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "myapp"
  vault.hashicorp.com/agent-configmap: "vault-agent-config"
  vault.hashicorp.com/agent-inject-secret-config.json: "secret/data/myapp/config"
  vault.hashicorp.com/agent-inject-template-config.json: |
    {
      {{- with secret "secret/data/myapp/config" -}}
      "username": "{{ .Data.data.username }}",
      "password": "{{ .Data.data.password }}",
      "api_key": "{{ .Data.data.api_key }}"
      {{- end -}}
    }
```

### Multiple Secrets

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "myapp"
  vault.hashicorp.com/agent-inject-secret-db-config: "secret/data/myapp/database"
  vault.hashicorp.com/agent-inject-secret-api-config: "secret/data/myapp/api"
  vault.hashicorp.com/agent-inject-template-db-config: |
    {{- with secret "secret/data/myapp/database" -}}
    DB_HOST={{ .Data.data.host }}
    DB_PORT={{ .Data.data.port }}
    DB_USER={{ .Data.data.username }}
    DB_PASS={{ .Data.data.password }}
    {{- end -}}
```

### Init Container Mode

For applications that need secrets available before the main container starts:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-pre-populate-only: "true"
  vault.hashicorp.com/role: "myapp"
  vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
```

## Troubleshooting

### Common Issues

1. **Injector pods not starting**
   ```bash
   oc describe pod -l app.kubernetes.io/name=vault-agent-injector -n vault
   oc logs -l app.kubernetes.io/name=vault-agent-injector -n vault
   ```

2. **Authentication failures**
   ```bash
   # Check Kubernetes auth configuration
   vault read auth/kubernetes/config
   
   # Test authentication
   vault write auth/kubernetes/login role=myapp jwt=<service-account-token>
   ```

3. **Secret injection not working**
   ```bash
   # Check if mutation webhook is configured
   oc get mutatingwebhookconfiguration
   
   # Check injector logs
   oc logs -l app.kubernetes.io/name=vault-agent-injector -n vault
   ```

4. **Pod annotation issues**
   ```bash
   # Verify pod annotations
   oc describe pod <pod-name>
   
   # Check if vault agent container was injected
   oc get pod <pod-name> -o jsonpath='{.spec.containers[*].name}'
   ```

### Debugging Commands

```bash
# Check Vault status
oc exec vault-0 -n vault -- vault status

# List auth methods
oc exec vault-0 -n vault -- vault auth list

# Check policies
oc exec vault-0 -n vault -- vault policy list
oc exec vault-0 -n vault -- vault policy read myapp-policy

# Test secret retrieval
oc exec vault-0 -n vault -- vault kv get secret/myapp/config
```

## Security Best Practices

1. **Use least privilege policies**
2. **Rotate service account tokens regularly**
3. **Use namespaced service accounts**
4. **Monitor Vault audit logs**
5. **Implement proper RBAC for Vault access**
6. **Use TLS for Vault communication in production**

## Additional Configuration

### Storage Classes

For persistent storage with specific storage classes:

```bash
# Check available storage classes
oc get storageclass

# Deploy with specific storage class
helm install vault hashicorp/vault \
  --namespace vault \
  --set "server.dataStorage.storageClass=gp2" \
  --set "server.auditStorage.storageClass=gp2"
```

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-network-policy
  namespace: vault
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vault
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: vault
    - namespaceSelector:
        matchLabels:
          vault-injection: enabled
  egress:
  - {}
```

### Service Mesh Integration

If using OpenShift Service Mesh (Istio), add these annotations:

```yaml
annotations:
  sidecar.istio.io/inject: "false"  # For Vault server pods
  # or
  sidecar.istio.io/inject: "true"   # For application pods using injection
```

### Monitoring

Enable ServiceMonitor for Prometheus Operator:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault-metrics
  namespace: vault
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault
  endpoints:
  - port: http
    path: /v1/sys/metrics
    params:
      format: ['prometheus']
```

## Production Considerations

1. **High Availability**: Deploy Vault with HA backend (Consul, etcd)
2. **TLS Configuration**: Enable TLS for all Vault communication
3. **Monitoring**: Set up monitoring for Vault and injector components
4. **Backup**: Implement regular backup strategy for Vault data
5. **Resource Limits**: Set appropriate resource requests and limits
6. **Network Policies**: Implement network policies to restrict traffic
7. **Security Context Constraints**: Ensure proper SCCs are configured
8. **Service Mesh**: Consider integration with OpenShift Service Mesh

## Troubleshooting

### Service Account Ownership Issues

If you get "invalid ownership metadata" errors during Helm installation:

```bash
# Delete existing service accounts if they exist without proper Helm labels
oc delete serviceaccount vault-server vault-agent-injector -n vault --ignore-not-found

# Or add Helm metadata to existing service accounts
oc label serviceaccount vault-server -n vault app.kubernetes.io/managed-by=Helm --overwrite
oc label serviceaccount vault-agent-injector -n vault app.kubernetes.io/managed-by=Helm --overwrite
oc annotate serviceaccount vault-server -n vault meta.helm.sh/release-name=vault --overwrite
oc annotate serviceaccount vault-server -n vault meta.helm.sh/release-namespace=vault --overwrite
oc annotate serviceaccount vault-agent-injector -n vault meta.helm.sh/release-name=vault --overwrite
oc annotate serviceaccount vault-agent-injector -n vault meta.helm.sh/release-namespace=vault --overwrite
```

### Image Pull Issues

If you encounter image pull errors like "Image not found" from Red Hat registry:

```bash
# Check current image configuration
oc describe pod vault-0 -n vault | grep Image

# Method 1: Uninstall and reinstall with explicit Docker Hub registry
helm uninstall vault -n vault
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.image.repository=docker.io/hashicorp/vault" \
  --set "server.image.tag=1.15.6" \
  --set "server.standalone.enabled=true" \
  --set "injector.image.repository=docker.io/hashicorp/vault-k8s" \
  --set "injector.image.tag=1.3.1" \
  --set "injector.replicas=1" \
  --reuse-values

# Method 2: Use alternative working images
helm install vault hashicorp/vault \
  --namespace vault \
  --set "global.openshift=true" \
  --set "server.image.repository=vault" \
  --set "server.image.tag=1.15.6" \
  --set "server.standalone.enabled=true" \
  --set "injector.image.repository=hashicorp/vault-k8s" \
  --set "injector.image.tag=1.3.1" \
  --set "injector.replicas=1"

# Method 3: Check available images in your cluster
oc get images | grep vault

# Method 4: Use ImageStream if available
oc import-image vault:1.15.6 --from=docker.io/hashicorp/vault:1.15.6 --confirm
```

### Pod Anti-Affinity Issues (HA Deployment)

If you see "didn't match pod anti-affinity rules" errors in a multi-node HA setup:

```bash
# Check if you have enough nodes
oc get nodes | grep Ready | wc -l

# If you have less than 3 nodes, switch to standalone mode
helm uninstall vault -n vault
# Then reinstall using the Single-Node configuration from Step 2

# Or disable anti-affinity (not recommended for production)
helm upgrade vault hashicorp/vault \
  --namespace vault \
  --set "server.affinity.podAntiAffinity=" \
  --reuse-values
```

### SCC Issues

```bash
# Check if pods have proper SCC
oc describe pod vault-0 -n vault | grep scc

# Check SCC assignments
oc describe scc vault-scc
```

### Route Access Issues

If you get "This site can't provide a secure connection" or similar SSL/TLS errors when accessing the Vault Web UI:

```bash
# Check route status and TLS configuration
oc get routes -n vault
oc describe route vault -n vault

# Fix: Change from passthrough to edge TLS termination
oc patch route vault -n vault -p '{"spec":{"tls":{"termination":"edge","insecureEdgeTerminationPolicy":"Redirect"}}}'

# Test route connectivity
curl -k https://$(oc get route vault -n vault -o jsonpath='{.spec.host}')
```

**Root Cause**: The default Vault Helm chart creates a route with `passthrough` TLS termination, expecting Vault to handle TLS directly. However, our configuration serves HTTP on port 8200, so the route needs `edge` termination to handle TLS at the OpenShift router level.

### Agent Injector Image Pull Issues

If you encounter `ImagePullBackOff` errors for vault agent containers, verify the agent image configuration:

```bash
# Check current agent image setting
oc get deployment vault-agent-injector -n vault -o yaml | grep AGENT_INJECT_VAULT_IMAGE -A1

# If the image doesn't have docker.io prefix, update it via Helm
helm upgrade vault hashicorp/vault \
  --namespace vault \
  --reuse-values \
  --set "injector.agentImage.repository=docker.io/hashicorp/vault" \
  --set "injector.agentImage.tag=1.15.6"

# Restart the injector deployment
oc rollout restart deployment vault-agent-injector -n vault

# Delete affected application pods to recreate them
oc delete pods -l app=myapp -n <namespace>
```

### Single-Node Cluster Pod Anti-Affinity Issues

For single-node clusters, if you see `FailedScheduling` events due to anti-affinity rules:

```bash
# Check for anti-affinity scheduling failures
oc describe pods -n vault | grep -A5 -B5 "anti-affinity"

# Solution: Reduce replica count to 1
helm upgrade vault hashicorp/vault \
  --namespace vault \
  --reuse-values \
  --set "injector.replicas=1"
```

### HA Cluster Initialization Issues

If you encounter Consul connection errors or initialization failures in HA mode:

```bash
# Check if Raft is properly configured
oc get statefulset vault -n vault -o yaml | grep -A5 -B5 raft

# If Raft is not enabled, you need to reinstall with proper configuration
helm uninstall vault -n vault
# Wait for pods to terminate completely
oc get pods -n vault --watch

# Reinstall with Raft enabled (critical for HA)
helm install vault hashicorp/vault \
  --namespace vault \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true" \
  # ... other settings

# Check pod logs for Raft cluster formation
oc logs vault-0 -n vault | grep -i raft
oc logs vault-1 -n vault | grep -i raft
oc logs vault-2 -n vault | grep -i raft

# Verify cluster peers after initialization
oc exec vault-0 -n vault -- vault operator raft list-peers
```

**Common HA Issues:**
- **Missing Raft Configuration**: Ensure `server.ha.raft.enabled=true` is set
- **Consul Errors**: These indicate missing Raft backend; reinstall with Raft
- **StatefulSet Update Limitations**: HA configuration changes require complete reinstallation
- **Pod Anti-Affinity**: Ensure you have 3+ schedulable nodes for HA deployment

### Authentication Issues

If applications can't authenticate with Vault:

```bash
# Verify Kubernetes auth configuration
oc exec vault-0 -n vault -- vault read auth/kubernetes/config

# Check service account and role configuration
oc exec vault-0 -n vault -- vault read auth/kubernetes/role/myapp

# Verify service account exists in application namespace
oc get serviceaccount myapp -n default

# Check application pod logs for authentication errors
oc logs -f <pod-name> -c vault-agent-init -n default
```

### Verification Commands

After successful deployment, use these commands to verify the setup:

```bash
# Check all Vault components are running
oc get pods -n vault

# Verify injector is ready
oc get pods -n vault -l app.kubernetes.io/name=vault-agent-injector

# Test secret injection in application
oc exec <app-pod> -c <app-container> -- cat /vault/secrets/config.txt

# Check Vault status
oc exec vault-0 -n vault -- vault status
```

## Summary

This guide provides a complete, tested setup for Vault Agent Injector on OpenShift. Key points for success:

### ✅ Validated Configuration
- **Container Images**: All images explicitly use `docker.io` registry to avoid Red Hat registry conflicts
- **Agent Image**: Correctly configured via `injector.agentImage.repository` and `injector.agentImage.tag`
- **Single-Node Support**: Proper replica configuration and anti-affinity handling
- **Authentication**: Simplified Kubernetes auth method configuration
- **Template Formatting**: Proper Go template syntax with correct whitespace handling

### 🔧 Key OpenShift Adaptations
- Custom SecurityContextConstraints (SCC) for Vault requirements
- Explicit registry specification for all container images
- OpenShift Route configuration for UI access
- Service account creation with proper Helm ownership labels

### 🚀 Production Considerations
- Use HA configuration (`server.ha.enabled=true`) for multi-node clusters
- Implement proper backup strategies for Vault data
- Configure TLS certificates for production deployments
- Review and customize resource limits based on workload requirements
- Implement monitoring and alerting for Vault components

The setup has been thoroughly tested with successful secret injection into application pods, demonstrating that the Vault Agent Injector is fully functional on OpenShift.

This completes the Vault Agent Injector setup guide for OpenShift. The injector will now automatically inject secrets into pods that have the appropriate annotations.