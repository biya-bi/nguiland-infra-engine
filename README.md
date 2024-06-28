# Introduction

This project is an infrastructure engine. Its purpose is to drive act on an infrastructure based on certain events.

# Secret as Code use case
It can help implement Secret as Code projects in a simple but secure way. By so doing, secrets can be kept encrypted in the Git repository and their life cycles managed via pull requests. With this approach, we can take advantage of GitOps tools such as [Flux](https://fluxcd.io/flux/) which will decrypt the secrets and apply the decrypted secrets to a Kubernetes cluster for example.

# Preparing the Kubernetes cluster

Let's assume the following:
- We want to implement GitOps on a Kubernetes cluster.
- We want to use a personal GitHub repository as our source of truth.
- We want to use [sops](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age) for secret encryption on decryption.

Using Flux 2.3.0, we can achieve our goal by carrying out the below steps:

## Step 1: Bootstrap Flux
This step assumes that you have your GitHub token exported to an environment variable.

For more references, visit [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/)

For example:

```
export GITHUB_TOKEN=<gh-token>
```

```
flux bootstrap github \
  --token-auth \
  --owner=<github_account_owner> \
  --repository=<github_repository> \
  --branch=main \
  --path=clusters/<cluster_name> \
  --personal
```

## Step 2: Generate an age private-public key pair if none exists yet
For example:
```
age-keygen -o keys.txt
```

## Step 3: Make sure to move the generated keys file to a secure location and point the SOPS_AGE_KEY_FILE environment variable to its location.
For example:
```
export SOPS_AGE_KEY_FILE="${HOME}/.sops/age/keys.txt"
```

## Step 4: Create a Kubernete secret with identity.agekey as key and the age private key as value
For example:
```
kubectl create secret generic sops-age --namespace=flux-system --from-literal=identity.agekey=<AGE_PRIVATE_KEY>
```

## Step 5: Update the flux kustomization generated in step 1 by adding a decryption section to the yaml, commit and push the changes
For example:
```
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/dev # We have assumed that dev is the cluster name that was used in step 1
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  # Here is the decryption configuration
  decryption:
    provider: sops # We are using the sops provider
    secretRef:
      name: sops-age # This is the secret name that was used in step 4
```

# Reconciling the Kubernetes cluster with the Git repository
Each time a commit is pushed to the branch tracked by Flux, flux will do the reconciliation after some time. But if we don't want to wait for Flux to do that automatically, we can run the below commands:

```
# Manually launch the reconcilation
flux reconcile kustomization flux-system --timeout 60s

# Monitor the reconcialation
flux get kustomization flux-system
```
