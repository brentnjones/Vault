# Vault Agent Injector on OpenShift - Overview for Customers

## What This Documentation Accomplishes

This guide sets up **automatic secret injection** for your applications running on OpenShift. Instead of manually managing secrets in your application code, Vault will automatically provide them to your containers.

## The Big Picture: What You're Building

### Before Setup (Traditional Approach)
- Applications need to connect to Vault directly
- Developers must write code to authenticate and retrieve secrets
- Applications need Vault tokens and connection details
- Updates to secrets require application restarts or manual processes

### After Setup (With Agent Injector)
- **Zero code changes** required in applications
- Secrets automatically appear as files inside containers
- Vault handles authentication using OpenShift's built-in service accounts
- Secret updates happen automatically without restarts
- Applications just read files - no Vault knowledge needed

## What This Guide Sets Up

### 1. **Vault Server** (Your Secret Storage)
- Secure storage for passwords, API keys, certificates, etc.
- Web UI for managing secrets
- High availability configuration for production use

### 2. **Vault Agent Injector** (The Magic Component)
- Watches for new application deployments
- Automatically adds secret-fetching containers to your pods
- Handles authentication with Vault using OpenShift credentials
- Renders secrets into files your applications can read

### 3. **Security Integration** (OpenShift-Specific)
- Custom security policies that allow Vault to run safely
- Service accounts with proper permissions
- Network routing for secure access

## How It Works (Simple Explanation)

### Step 1: Store Secrets
You put secrets into Vault (passwords, API keys, etc.)

### Step 2: Annotate Your Applications
Add special labels to your application deployments telling Vault:
- Which secrets you need
- Where to put them in your container
- How to format them

### Step 3: Deploy Applications
When you deploy, the Agent Injector automatically:
- Adds a helper container that fetches secrets from Vault
- Authenticates using OpenShift's built-in service accounts
- Puts secrets into files inside your application container

### Step 4: Applications Read Files
Your application simply reads secret files from `/vault/secrets/` directory

## Example: Before and After

### Before (Traditional Way)
```python
# Application needs Vault libraries and connection code
import hvac
client = hvac.Client(url='https://vault.company.com')
client.token = 'vault-token-here'
secret = client.secrets.kv.v2.read_secret_version(path='myapp/config')
password = secret['data']['data']['password']
```

### After (With Agent Injector)
```python
# Application just reads a file - no Vault knowledge needed!
with open('/vault/secrets/config.txt', 'r') as f:
    config = f.read()
    # File contains: password=mypassword
```

## What Each Step in the Documentation Does

### Steps 1-3: **Foundation Setup**
- Creates a dedicated project/namespace for Vault
- Sets up security permissions (OpenShift-specific requirements)
- Creates service accounts for Vault components

### Step 4: **Install Vault**
- Deploys Vault server and Agent Injector using Helm charts
- Configures them specifically for OpenShift environments
- Sets up web UI and network routes

### Step 5: **Initialize Security**
- Creates the master encryption key for Vault
- Enables authentication using OpenShift service accounts
- No external authentication systems required

### Steps 6-7: **Configure for Applications**
- Creates policies (rules about who can access what secrets)
- Stores example secrets for testing
- Links OpenShift service accounts to Vault permissions

### Steps 8-9: **Test It Works**
- Deploys a sample application with secret injection annotations
- Verifies secrets appear automatically in the container
- Confirms the complete workflow functions

## Key Benefits for Your Organization

### **For Developers**
- No Vault knowledge required in application code
- Secrets appear as simple files
- No authentication code to write or maintain
- Works with any programming language

### **For Operations**
- Centralized secret management
- Automatic secret rotation capabilities
- Audit trails for secret access
- No secrets stored in container images or environment variables

### **For Security**
- Secrets never stored in plain text in OpenShift
- Automatic encryption at rest and in transit
- Fine-grained access controls
- Integration with OpenShift's security model

## Important Notes for OpenShift Environments

This documentation has been specifically tested and optimized for OpenShift, including:
- **Container Registry Settings**: Uses Docker Hub instead of Red Hat registry
- **Security Context Constraints**: Custom policies for Vault's requirements
- **Single-Node Compatibility**: Works on development clusters like CodeReady Containers
- **Route Configuration**: Automatic HTTPS endpoints for Vault UI

## What You Need to Get Started

- OpenShift 4.x cluster with admin access
- Helm 3.x installed on your workstation
- Basic familiarity with `oc` command line tool
- About 30-45 minutes to complete the setup

## Success Criteria

After following this guide, you'll have:
- ✅ Vault running securely on OpenShift
- ✅ Web UI accessible for secret management
- ✅ Agent Injector ready to inject secrets into applications
- ✅ Working example application with automatically injected secrets
- ✅ Complete troubleshooting guide for common issues

This setup provides the foundation for secure, automated secret management across all your OpenShift applications.