#!/usr/bin/env bash

kubectl delete validatingwebhookconfigurations kyverno-resource-validating-webhook-cfg validate.kyverno.svc-fail --ignore-not-found
kubectl delete mutatingwebhookconfigurations kyverno-resource-mutating-webhook-cfg kyverno-policy-mutating-webhook-cfg --ignore-not-found
kubectl delete validatingwebhookconfigurations kyverno-policy-validating-webhook-cfg --ignore-not-found
kubectl delete validatingwebhookconfigurations ingress-nginx-admission --ignore-not-found
kubectl delete validatingwebhookconfigurations config.webhook.pipeline.tekton.dev --ignore-not-found
kubectl delete mutatingwebhookconfigurations webhook.pipeline.tekton.dev --ignore-not-found

flux uninstall --namespace infra --silent
flux uninstall --namespace kyverno --silent
flux uninstall --namespace flux-system --silent
