#!/bin/bash

function removeFolder {
  # Remove a folder if it exists
  
    folder=$1
    if [ -d "$folder" ]; then
        # delete the folder if it exists
        rm -rf ${folder}
        echo "Removed ${folder}..."
    fi
}

k8sconf=$1
# Set Kubectl config file path
export KUBECONFIG=$k8sconf

# Delete argo workflows
argo delete --all 
argo delete -n two --all 
argo delete -n three --all 

# Uninstall HF networks on the different clusters (namespaces)
helm uninstall hlf-kube
helm uninstall hlf-kube-two -n two
helm uninstall hlf-kube-three -n three

# Uninstall the Ingress Controllers
helm uninstall hlf-peer-ingress -n kube-system 
helm uninstall hlf-orderer-ingress -n kube-system 

# Delete Argo Resources from K8s cluster
kubectl delete -n argo -f https://raw.githubusercontent.com/argoproj/argo/stable/manifests/install.yaml
kubectl delete -n default default-admin
kubectl delete -n two default-admin
kubectl delete -n three default-admin

# Delete K8s namespaces
kubectl delete ns two
kubectl delete ns three
kubectl delete ns argo

# Remove folders that were created during setup script
removeFolder fabric-kube-two
removeFolder fabric-kube-three