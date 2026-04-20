#!/usr/bin/env bash

flux uninstall --namespace flux-system --silent
flux uninstall --namespace infra --silent
flux uninstall --namespace kyverno --silent

kubectl get validatingwebhookconfigurations -o name | xargs -I {} kubectl delete {}
kubectl get mutatingwebhookconfigurations -o name | xargs -I {} kubectl delete {}
kubectl get crds -o name | xargs -I {} kubectl delete {}
