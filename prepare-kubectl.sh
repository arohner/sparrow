#!/bin/bash

CONTEXT="$1"

mkdir ~/.kube
echo $KUBECONFIG_DATA | base64 --decode > ~/.kube/config

sudo /opt/google-cloud-sdk/bin/gcloud --quiet components update kubectl

# sanity check kubectl and its connection to the kubernetes API
kubectl version
kubectl config use-context $CONTEXT
kubectl cluster-info
