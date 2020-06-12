# Hyperledger Fabric meets Kubernetes

Check out `ORIGINAL-README.md` for the original README and additional setup possiblities.

## Abbreviations
Hyperledger Fabric - *HF*

Kubernetes - *K8s*

## Requirements
* A running Kubernetes Cluster
* [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) same version as your K8s cluster (we used 1.17.5)
* [Helm 3](https://helm.sh/docs/intro/install/)
* [jq](https://stedolan.github.io/jq/download/) 1.5+
* [yq](https://pypi.org/project/yq/) 2.6+
* [Argo CLI](https://github.com/argoproj/argo/blob/master/docs/getting-started.md), CLI 2.4.0+ (Argo Controller gets installed automatically by setup script)
* Run all the commands in *fabric-kube* folder
* AWS EKS users please also apply this [fix](https://github.com/APGGroeiFabriek/PIVT/issues/1)

## Quickstart
This quickstart sets up a Hyperledger Fabric network
on one Kubernetes Cluster in three different namespaces.

You need a running K8s cluster, and the path to the K8s config file.

Open the terminal and type:
```
./setup_cross_cluster_on_one_cluster.sh ~/path/to/YOUR-CLUSTER-kubeconfig.yaml
```

Then let it run, and watch out for any errors.

---

To quickly remove all HF related resources from your K8s cluster:
```
./teardown_cross_cluster_on_one_cluster.sh ~/path/to/YOUR-CLUSTER-kubeconfig.yaml
```