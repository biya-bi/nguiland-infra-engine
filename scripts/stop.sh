#!/usr/bin/env bash

flux uninstall --namespace flux-system --silent
flux uninstall --namespace infra --silent
flux uninstall --namespace kyverno --silent
flux uninstall --namespace tekton-pipelines --silent

kubectl delete validatingwebhookconfigurations --all
kubectl delete mutatingwebhookconfigurations --all

kubectl get crds -o name | xargs -I {} kubectl delete {}

kubectl delete namespace tekton-dashboard tekton-pipelines tekton-pipelines-resolvers --ignore-not-found
