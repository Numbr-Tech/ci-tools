# ci-tools

## Déployer votre application via github workflow

1. créer un fichier Infra/containerapp.yaml.tpl
```yaml
name: __PROJECT_NAME__
type: Microsoft.App/containerApps
location: __AZURE_LOCATION__
identity:
  type: UserAssigned
  userAssignedIdentities:
    /subscriptions/__AZURE_SUBSCRIPTION_ID__/resourceGroups/__AZURE_SHARED_RESOURCE_GROUP__/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mid-frc-iac: {}
properties:
  environmentId: /subscriptions/__AZURE_SUBSCRIPTION_ID__/resourceGroups/__AZURE_RESOURCE_GROUP__/providers/Microsoft.App/managedEnvironments/__AZURE_CONTAINERAPP_ENVIRONMENT_NAME__
  configuration:
    secrets:
      - name: MY_SECRET
        identity: "/subscriptions/${{ env.AZURE_SUBSCRIPTION_ID }}/resourceGroups/${{ env.AZURE_RESOURCE_GROUP }}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mid-frc-iac"
        keyVaultUrl: "https://${{ env.AZURE_VAULT_NAME }}.vault.azure.net/secrets/MY_SECRET"
    ingress:
      allowInsecure: false
      external: __INGRESS_EXTERNAL__
      targetPort: __INGRESS_PORT__
    registries:
      - server: __AZURE_REGISTRY_FQDN__
        identity: /subscriptions/__AZURE_SUBSCRIPTION_ID__/resourceGroups/__AZURE_SHARED_RESOURCE_GROUP__/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mid-frc-iac
template:
  containers:
    - image: __AZURE_REGISTRY_FQDN__/__PROJECT_NAME__:__IMAGE_TAG__
      name: __PROJECT_NAME__
      resources:
        cpu: "__RESOURCE_CPU__"
        memory: "__RESOURCE_MEMORY__"
      env:
        - name: "INFRA_ENV"
          value: "__INFRA_ENV__"
  scale:
    minReplicas: __SCALE_MIN_REPLICATS__
    maxReplicas: __SCALE_MAX_REPLICATS__
    rules:
      - name: "http-scaler"
        http:
          metadata:
            concurrentRequests: "__SCALE_CONCURRENT_REQUEST__"
```

2. ajouter dans votre projet un fichier .github/workflows/deploy.yml

```yaml
name: Deploy

on:
  push:
    branches:
      - staging
      - main
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    uses: Numbr-Tech/ci-tools/.github/workflows/_templates-deploy-simple.yml@v1
    with:
      PROJECT_NAME: le-nom-de-votre-projet
      # vous pouvez surcharger les valeurs par defaut des paramètre définis ici https://github.com/Numbr-Tech/ci-tools/blob/main/.github/workflows/_templates-deploy-simple.yml
    secrets:
      secrets: inherit
      # ou de manière explicite
      # AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }} # demande à Gregory CADICI de le setter dans les settings de ton repo github 
      # AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      # AZURE_SUBSCRIPTION_ID_PPROD: ${{ secrets.AZURE_SUBSCRIPTION_ID_PPROD }}
      # AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```