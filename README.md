# Introduction

This project is a Flux-based GitOps repository. Its purpose is to drive infrastructure deployments based on Git events.

# Cluster Setup and Operations

All cluster preparation, bootstrapping, and operational steps are contained within the [nguiland-ops-deploy](https://github.com/biya-bi/nguiland-ops-deploy) repository.

Please refer to that repository for:
- Secret encryption setup (SOPS and Age).
- Flux bootstrapping and initialization (automated via `run.sh`).
- Deployment and reconciliation automation (`deploy.sh` implicitly called by `run.sh`).
- Maintenance and teardown utilities.
