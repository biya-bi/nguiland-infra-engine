#!/usr/bin/env bash

flux uninstall --namespace flux-system --silent
flux uninstall --namespace infra --silent
flux uninstall --namespace kyverno --silent

kubectl delete validatingwebhookconfigurations --all
kubectl delete mutatingwebhookconfigurations --all

kubectl get crds -o name | xargs -I {} kubectl delete {}
