# Deployer votre application avec ci-tools

1. Dupliquer le ticket https://manakin.atlassian.net/browse/NT-31 et mettre à jour les informations. Informerles devops (Gregory CADICI)

2. Créer un fichier Infra/values.yaml afin de spécifier vos resources Azure.

    ```yaml
    name: "hiive-api"
    #location: "francecentral"
    #vnet:
    #  name: "vnet-frc-hiive-api"
    #  subnet:
    #    name: "subnet-app"
    #resourceGroup:
    #  current:
    #    name: "rg-frc-hiive"
    #  shared:
    #    name: "rg-frc-pprodgeneral"
    #appEnv:
    #  internalOnly: false
    #ingress:
    #  port: 80
    #  external: true
    #vault:
    #  name: "key-frc-hiive"
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
          php: ~
          nginx: ~
    #        resources:
    #          cpu: '0.25'
    #          memory: '0.5Gi'
      staging:
        components:
          php: ~
          nginx: ~
    ```
3. Créer vos Dockerfile. Ils doivent suivre cette règle de nomage : `Dockerfile.{{ components_name }}`. Dans notre exemple, compenent_name peut prendre les valeurs nginx ou php.
 
   Via`<project>-<coponent>:<port>`, vous pouvez accéder à un container. Dans notre exemple cela donnerait : `hiive-api-php:9000`.

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

