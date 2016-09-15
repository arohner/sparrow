#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# $1 = the kubernetes context (specified in kubeconfig)
# $2 = directory that contains your kubernetes files to deploy
# $3 = pass in rolling to perform a rolling update

# Uses environment variables:
# SERVICENAME: name of the kube service, and default name for all kube files
# IMAGE_REPO name of the docker image to sed when updating version
# IMAGE_TAG name of the *existing* version tag to replace in the deployment. Will be replaced with the contents of $BUILD
# CONFIGMAP path to the configmap.yml, kube/${CONFIGMAP}.configmap.yml, defaults to SERVICENAME
# DEPLOYMENT path to the deployment.yml kube/${DEPLOYMENT}.deployment.yml, defaults to SERVICENAME
# BUILD docker image tag to be deployed.


set -euo pipefail

DEPLOY_TIMEOUT=${DEPLOY_TIMEOUT:-300}
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CONTEXT="$1"
ROLLING=$(echo "${2:0:7}" | tr '[:upper:]' '[:lower:]')
CONFIGMAP=${CONFIGMAP:-${SERVICENAME}}
DEPLOYMENT=${DEPLOYMENT:-${SERVICENAME}}

~/.kube/kubectl version
~/.kube/kubectl config use-context ${CONTEXT}

#get user, password, certs, namespace and api ip from config data
export kubepass=`(~/.kube/kubectl config view -o json --raw --minify  | jq .users[0].user.password | tr -d '\"')`

export kubeuser=`(~/.kube/kubectl config view -o json --raw --minify  | jq .users[0].user.username | tr -d '\"')`

export kubeurl=`(~/.kube/kubectl config view -o json --raw --minify  | jq .clusters[0].cluster.server | tr -d '\"')`

export kubenamespace=`(~/.kube/kubectl config view -o json --raw --minify  | jq .contexts[0].context.namespace | tr -d '\"')`

export kubeip=`(echo $kubeurl | sed 's~http[s]*://~~g')`

export https=`(echo $kubeurl | awk 'BEGIN { FS = ":" } ; { print $1 }')`

export certdata=`(~/.kube/kubectl config view -o json --raw --minify  | jq '.users[0].user["client-certificate-data"]' | tr -d '\"')`

export certcmd=""

echo "rolling = $ROLLING"

if [ "$certdata" != "null" ] && [ "$certdata" != "" ];
then
    ~/.kube/kubectl config view -o json --raw --minify  | jq '.users[0].user["client-certificate-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-cert.pem
    export certcmd="$certcmd --cert ${CONTEXT}-cert.pem"
fi

export keydata=`(~/.kube/kubectl config view -o json --raw --minify  | jq '.users[0].user["client-key-data"]' | tr -d '\"')`

if [ "$keydata" != "null" ] && [ "$keydata" != "" ];
then
   ~/.kube/kubectl config view -o json --raw --minify  | jq '.users[0].user["client-key-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-key.pem
    export certcmd="$certcmd --key ${CONTEXT}-key.pem"
fi

export cadata=`(~/.kube/kubectl config view -o json --raw --minify  | jq '.clusters[0].cluster["certificate-authority-data"]' | tr -d '\"')`

if [ "$cadata" != "null" ] && [ "$cadata" != "" ];
then
    ~/.kube/kubectl config view -o json --raw --minify  | jq '.clusters[0].cluster["certificate-authority-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-ca.pem
    export certcmd="$certcmd --cacert ${CONTEXT}-ca.pem"
fi

#print some useful data for folks to check on their service later

# Ensure configmaps are applied
~/.kube/kubectl apply -f kube/${CONFIGMAP}.configmap.yml

echo "Ensure Deployment"
# Ensure deployment exists, create it if not
~/.kube/kubectl get deployment ${SERVICENAME} &>/dev/null
if [ $? -ne 0 ]
then
  echo "Deployment does not exist yet, creating it"
  ~/.kube/kubectl create -f kube/${DEPLOYMENT}.deployment.yml --record
else
  echo "Deployment already exists, continuing"
fi

if [ "${ROLLING}" = "rolling" ]
then
  echo "rolling deploy"
  # perform a rolling update by updating the Deployment
  sed -e "s|${IMAGE_REPO}:${IMAGE_TAG}|${IMAGE_REPO}:${BUILD}|g;" kube/${DEPLOYMENT}.deployment.yml > kube/${DEPLOYMENT}.deployment.${BUILD}.yml
  ~/.kube/kubectl apply -f kube/${DEPLOYMENT}.deployment.${BUILD}.yml
fi

$DIR/timeout.sh -t ${DEPLOY_TIMEOUT} $DIR/verify-deployment.sh ${CONTEXT}
result=$?
if [ "$result" == "143" ] ; then
    echo "------- DEPLOYMENT TIMEOUT FAIL --------"
    exit 1
fi
if [ "$result" == "0" ] ; then
  echo "DEPLOY SUCCESFULL"
  exit 0
fi
echo "DEPLOY FAILED"
exit $result
