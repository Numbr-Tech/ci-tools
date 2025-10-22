# Deployer votre application avec ci-tools

1. Dupliquer le ticket https://manakin.atlassian.net/browse/NT-31 et mettre à jour les informations. Informerles devops (Gregory CADICI)

2. Créer un fichier Infra/values.yaml

    ```yaml
    name: "giwb-api"
    #location: "francecentral"
    #vnet:
    #  name: "vnet-frc-legacy"
    #  subnet:
    #    name: "subnet-app"
    #resourceGroup:
    #  current:
    #    name: "rg-frc-legacy"
    #  shared:
    #    name: "rg-frc-pprodgeneral"
    #appEnv:
    #  internalOnly: false
    #ingress:
    #  port: 80
    #  external: true
    vault:
      #name: "key-frc-legacy"
    envVariables:
      - name: MY_VAR
        value: "foo"
      - name: MY_VAR_FROM_VAULT
        secretRef: my-secret
    env:
      production:
    #    autoscaling:
    #      min: '3'
    #      max: '10'
    #      concurrent_requests: '30'
        components:
          nginx: ~
    #        resources:
    #          cpu: '0.25'
    #          memory: '0.5Gi'
      staging:
        components:
          nginx: ~
    ```

4. Ajouter dans votre projet un fichier `.github/workflows/deploy.yml`.

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
           uses: Numbr-Tech/ci-tools/.github/workflows/_templates-deploy-simple.yml@v2
           secrets: inherit
   ```

