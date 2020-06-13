#!/bin/bash

##########################################################################################################################################
# HELPERS
##########################################################################################################################################

function removeFolder {
  # Remove a folder if it exists
  
    folder=$1
    if [ -d "$folder" ]; then
        # delete the folder if it exists
        rm -rf ${folder}
        echo "Removed ${folder}..."
    fi
}

function waitForExternalIPs {
  # Wait until external IPs switch from "pending" to an actual IP

  echo 
  echo "wait for external IP creation..."
  all_pods_ready=$(kubectl get svc -A | grep '<pending>')
  while [ "$all_pods_ready" != "" ]
  do 
    sleep 10
    all_pods_ready=$(kubectl get svc -A | grep '<pending>')
  done
  echo "External IPs successfully created!"
}


function waitUntilAllPodsRun {
  # Wait until all pods are running

  echo 
  echo "wait for pod creation..."
  all_pods_ready=$(kubectl get pods -A | grep '0/')
  while [ "$all_pods_ready" != "" ]
  do 
    sleep 10
    all_pods_ready=$(kubectl get pods -A | grep '0/')
  done
}

##########################################################################################################################################
# PREPARE K8s and FOLDER
##########################################################################################################################################

# Constants
k8sconf=$1
clusterOnePath="$PWD/fabric-kube/"
clusterTwoPath="$PWD/fabric-kube-two/"
clusterThreePath="$PWD/fabric-kube-three/"

# Set Kubectl config file path
export KUBECONFIG=$k8sconf

# update helm dependencies
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
cd $clusterOnePath
echo $PWD
helm dependency update hlf-kube/
cd ..

# Create namespaces
kubectl create ns two
kubectl create ns three
kubectl create ns argo

# Argo specific preparation
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo/stable/manifests/install.yaml
kubectl create rolebinding default-admin --clusterrole=admin --serviceaccount=default:default
kubectl create rolebinding default-admin --clusterrole=admin --serviceaccount=two:default --namespace=two
kubectl create rolebinding default-admin --clusterrole=admin --serviceaccount=three:default --namespace=three

# Setup folder structure with one directory per cluster (three directories, first one already exists)
removeFolder "fabric-kube-two"
removeFolder "fabric-kube-three"

cp -r fabric-kube/ fabric-kube-two/
cp -r fabric-kube/ fabric-kube-three/

# Install Ingress Controller
helm install hlf-peer-ingress stable/nginx-ingress --namespace kube-system --set controller.service.type=LoadBalancer --set controller.ingressClass=hlf-peer --set controller.service.ports.https=7051 --set controller.service.enableHttp=false --set controller.extraArgs.enable-ssl-passthrough=''
helm install hlf-orderer-ingress stable/nginx-ingress --namespace kube-system --set controller.service.type=LoadBalancer --set controller.ingressClass=hlf-orderer --set controller.service.ports.https=7050 --set controller.service.enableHttp=false --set controller.extraArgs.enable-ssl-passthrough=''

waitForExternalIPs

##########################################################################################################################################
# SETUP BARE BONES HF 
##########################################################################################################################################

# Crypto material and genesis block
cd $clusterOnePath
./init.sh samples/cross-cluster-raft-tls/cluster-one/ samples/chaincode/ false
cd $clusterTwoPath
./init.sh samples/cross-cluster-raft-tls/cluster-two/ samples/chaincode/ false
cd $clusterThreePath
./init.sh samples/cross-cluster-raft-tls/cluster-three/ samples/chaincode/ false

# Gather Certs for Genesis Block
cd $clusterOnePath
cp -r ../fabric-kube-two/hlf-kube/crypto-config/ordererOrganizations/pivt.nl/msp/* hlf-kube/crypto-config/ordererOrganizations/pivt.nl/msp/
cp -r ../fabric-kube-two/hlf-kube/crypto-config/peerOrganizations/atlantis.com/msp/* hlf-kube/crypto-config/peerOrganizations/atlantis.com/msp/
cp -r ../fabric-kube-three/hlf-kube/crypto-config/peerOrganizations/nevergreen.nl/msp/* hlf-kube/crypto-config/peerOrganizations/nevergreen.nl/msp/
cp ../fabric-kube-two/hlf-kube/crypto-config/ordererOrganizations/pivt.nl/orderers/orderer0.pivt.nl/tls/server.crt hlf-kube/crypto-config/ordererOrganizations/pivt.nl/orderers/orderer0.pivt.nl/tls/

# Create Genesis Block
cd $clusterOnePath
cd hlf-kube/
configtxgen -profile OrdererGenesis -channelID testchainid -outputBlock ./channel-artifacts/genesis.block
cd ../

# Distribute Genesis Block to other cluster folders
cp hlf-kube/channel-artifacts/genesis.block ../fabric-kube-two/hlf-kube/channel-artifacts/
cp hlf-kube/channel-artifacts/genesis.block ../fabric-kube-three/hlf-kube/channel-artifacts/

# Gather TLSRootCerts of each Peer to commmit/invoke chaincode (already done for cluster one above)
cd $clusterTwoPath
cp -r ../fabric-kube/hlf-kube/crypto-config/peerOrganizations/aptalkarga.tr/msp/* hlf-kube/crypto-config/peerOrganizations/aptalkarga.tr/msp/
cp -r ../fabric-kube-three/hlf-kube/crypto-config/peerOrganizations/nevergreen.nl/msp/* hlf-kube/crypto-config/peerOrganizations/nevergreen.nl/msp/
cd $clusterThreePath
cp -r ../fabric-kube/hlf-kube/crypto-config/peerOrganizations/aptalkarga.tr/msp/* hlf-kube/crypto-config/peerOrganizations/aptalkarga.tr/msp/
cp -r ../fabric-kube-two/hlf-kube/crypto-config/peerOrganizations/atlantis.com/msp/* hlf-kube/crypto-config/peerOrganizations/atlantis.com/msp/

# Put right Certs in cluster three so that he can connect to an external orderer
cd $clusterThreePath
cp ../fabric-kube-two/hlf-kube/crypto-config/ordererOrganizations/pivt.nl/msp/tlscacerts/* hlf-kube/crypto-config/ordererOrganizations/pivt.nl/msp/tlscacerts/

# Launch network parts in broken state (because they don't have IPs yet)
cd $clusterOnePath
helm install hlf-kube ./hlf-kube -f samples/cross-cluster-raft-tls/cluster-one/network.yaml -f samples/cross-cluster-raft-tls/cluster-one/crypto-config.yaml --set peer.launchPods=false --set orderer.launchPods=false
cd $clusterTwoPath
helm install hlf-kube-two ./hlf-kube --namespace two -f samples/cross-cluster-raft-tls/cluster-two/network.yaml -f samples/cross-cluster-raft-tls/cluster-two/crypto-config.yaml --set peer.launchPods=false --set orderer.launchPods=false --set peer.externalService.enabled=true --set orderer.externalService.enabled=true
cd $clusterThreePath
helm install hlf-kube-three ./hlf-kube --namespace three -f samples/cross-cluster-raft-tls/cluster-three/network.yaml -f samples/cross-cluster-raft-tls/cluster-three/crypto-config.yaml --set peer.launchPods=false --set orderer.launchPods=false

##########################################################################################################################################
# UPGRADE the NETWORKS with HOST ALIASES so they can CONNECT TO EACH OTHER
##########################################################################################################################################

waitForExternalIPs

# Collect host aliases
cd $clusterOnePath
./collect_host_aliases.sh samples/cross-cluster-raft-tls/cluster-one/
./collect_external_host_aliases.sh ingress samples/cross-cluster-raft-tls/cluster-one/ 
cd $clusterTwoPath
./collect_host_aliases.sh samples/cross-cluster-raft-tls/cluster-two/ --namespace two
./collect_external_host_aliases.sh loadbalancer samples/cross-cluster-raft-tls/cluster-two/ --namespace two
cd $clusterThreePath
./collect_host_aliases.sh samples/cross-cluster-raft-tls/cluster-three/ --namespace three
./collect_external_host_aliases.sh ingress samples/cross-cluster-raft-tls/cluster-three/ --namespace three

# Merge host aliases together
cd $clusterOnePath
cat ../fabric-kube-two/samples/cross-cluster-raft-tls/cluster-two/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-one/hostAliases.yaml
cat ../fabric-kube-three/samples/cross-cluster-raft-tls/cluster-three/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-one/hostAliases.yaml
cd $clusterTwoPath
cat ../fabric-kube/samples/cross-cluster-raft-tls/cluster-one/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-two/hostAliases.yaml
cat ../fabric-kube-three/samples/cross-cluster-raft-tls/cluster-three/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-two/hostAliases.yaml
cd $clusterThreePath
cat ../fabric-kube/samples/cross-cluster-raft-tls/cluster-one/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-three/hostAliases.yaml
cat ../fabric-kube-two/samples/cross-cluster-raft-tls/cluster-two/externalHostAliases.yaml >> ./samples/cross-cluster-raft-tls/cluster-three/hostAliases.yaml

# Upgrade the networks
cd $clusterOnePath
helm upgrade hlf-kube ./hlf-kube -f samples/cross-cluster-raft-tls/cluster-one/network.yaml -f samples/cross-cluster-raft-tls/cluster-one/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-one/hostAliases.yaml --set peer.ingress.enabled=true --set orderer.ingress.enabled=true
cd $clusterTwoPath
helm upgrade hlf-kube-two ./hlf-kube -f samples/cross-cluster-raft-tls/cluster-two/network.yaml -f samples/cross-cluster-raft-tls/cluster-two/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-two/hostAliases.yaml --set peer.externalService.enabled=true --set orderer.externalService.enabled=true -n two
cd $clusterThreePath
helm upgrade hlf-kube-three ./hlf-kube -f samples/cross-cluster-raft-tls/cluster-three/network.yaml -f samples/cross-cluster-raft-tls/cluster-three/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-three/hostAliases.yaml --set peer.ingress.enabled=true -n three

##########################################################################################################################################
# ARGO WORKFLOWS
##########################################################################################################################################

# Create channels
cd $clusterOnePath
helm template channel-flow/ -f samples/cross-cluster-raft-tls/cluster-one/network.yaml -f samples/cross-cluster-raft-tls/cluster-one/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-one/hostAliases.yaml | argo submit - --watch
cd $clusterTwoPath
helm template channel-flow/ -f samples/cross-cluster-raft-tls/cluster-two/network.yaml -f samples/cross-cluster-raft-tls/cluster-two/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-two/hostAliases.yaml | argo submit - --namespace two --watch
cd $clusterThreePath
helm template channel-flow/ -f samples/cross-cluster-raft-tls/cluster-three/network.yaml -f samples/cross-cluster-raft-tls/cluster-three/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-three/hostAliases.yaml | argo submit - --namespace three --watch

# Install and Instantiate Chaincodes
cd $clusterOnePath
helm template chaincode-flow/ -f samples/cross-cluster-raft-tls/cluster-one/network.yaml -f samples/cross-cluster-raft-tls/cluster-one/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-one/hostAliases.yaml | argo submit - --watch
cd $clusterTwoPath
helm template chaincode-flow/ -f samples/cross-cluster-raft-tls/cluster-two/network.yaml -f samples/cross-cluster-raft-tls/cluster-two/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-two/hostAliases.yaml | argo submit - --namespace two --watch
cd $clusterThreePath
helm template chaincode-flow/ -f samples/cross-cluster-raft-tls/cluster-three/network.yaml -f samples/cross-cluster-raft-tls/cluster-three/crypto-config.yaml -f samples/cross-cluster-raft-tls/cluster-three/hostAliases.yaml | argo submit - --namespace three --watch

##########################################################################################################################################
# SUCCESS
##########################################################################################################################################

echo
echo "------------------------"
echo "SUCCESS!"
echo "You just spun up a cross-cluster Hyperledger Fabric network on Kubernetes, instantiated channels and run Chaincode."
