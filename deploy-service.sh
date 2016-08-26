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

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CONTEXT="$1"
DEPLOYDIR="$2"
ROLLING=$(echo "${3:0:7}" | tr '[:upper:]' '[:lower:]')

#make sure we have the kubectl comand
# chmod +x $DIR/ensure-kubectl.sh
# $DIR/ensure-kubectl.sh

#set config context
kubectl config use-context ${CONTEXT}
kubectl version

#get user, password, certs, namespace and api ip from config data
export kubepass=`(kubectl config view -o json --raw --minify  | jq .users[0].user.password | tr -d '\"')`

export kubeuser=`(kubectl config view -o json --raw --minify  | jq .users[0].user.username | tr -d '\"')`

export kubeurl=`(kubectl config view -o json --raw --minify  | jq .clusters[0].cluster.server | tr -d '\"')`

export kubenamespace=`(kubectl config view -o json --raw --minify  | jq .contexts[0].context.namespace | tr -d '\"')`

export kubeip=`(echo $kubeurl | sed 's~http[s]*://~~g')`

export https=`(echo $kubeurl | awk 'BEGIN { FS = ":" } ; { print $1 }')`

export certdata=`(kubectl config view -o json --raw --minify  | jq '.users[0].user["client-certificate-data"]' | tr -d '\"')`

export certcmd=""

if [ "$certdata" != "null" ] && [ "$certdata" != "" ];
then
    kubectl config view -o json --raw --minify  | jq '.users[0].user["client-certificate-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-cert.pem
    export certcmd="$certcmd --cert ${CONTEXT}-cert.pem"
fi

export keydata=`(kubectl config view -o json --raw --minify  | jq '.users[0].user["client-key-data"]' | tr -d '\"')`

if [ "$keydata" != "null" ] && [ "$keydata" != "" ];
then
    kubectl config view -o json --raw --minify  | jq '.users[0].user["client-key-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-key.pem
    export certcmd="$certcmd --key ${CONTEXT}-key.pem"
fi

export cadata=`(kubectl config view -o json --raw --minify  | jq '.clusters[0].cluster["certificate-authority-data"]' | tr -d '\"')`

if [ "$cadata" != "null" ] && [ "$cadata" != "" ];
then
    kubectl config view -o json --raw --minify  | jq '.clusters[0].cluster["certificate-authority-data"]' | tr -d '\"' | base64 --decode > ${CONTEXT}-ca.pem
    export certcmd="$certcmd --cacert ${CONTEXT}-ca.pem"
fi

#set -x

#print some useful data for folks to check on their service later
echo "Deploying service to ${https}://${kubeuser}:${kubepass}@${kubeip}/api/v1/proxy/namespaces/${kubenamespace}/services/${SERVICENAME}"
echo "Monitor your service at ${https}://${kubeuser}:${kubepass}@${kubeip}/api/v1/proxy/namespaces/kube-system/services/kibana-logging/?#/discover?_a=(columns:!(log),filters:!(),index:'logstash-*',interval:auto,query:(query_string:(analyze_wildcard:!t,query:'tag:%22kubernetes.${SERVICENAME}*%22')),sort:!('@timestamp',asc))"

if [ "${ROLLING}" = "rolling" ]
then
  # perform a rolling update by updating the Deployment
  sed 's/:latest/':${CIRCLE_SHA1}'/g;' ${DEPLOYDIR}/${SERVICENAME}.deployment.yml > ${DEPLOYDIR}/${SERVICENAME}.deployment.${CIRCLE_SHA1}.yml
  kubectl apply -f ${DEPLOYDIR}/${SERVICENAME}.deployment.${CIRCLE_SHA1}.yml
fi

# wait for services to start
# sleep 30

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
