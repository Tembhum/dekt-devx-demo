#!/usr/bin/env bash

AZURE_RESOURCE_GROUP="tap-aks"
AZURE_LOCATION="westus"
AWS_REGION="us-west-1" #aws ec2 describe-regions --output table
GKE_ZONE="us-west1-a"
GCP_PROJECT_ID="fe-asaikali"
TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)

#create-aks-cluster
create-aks-cluster() {

	cluster_name=$1
	number_of_nodes=$2

	scripts/printmsg.sh "Creating AKS cluster named $cluster_name with $number_of_nodes nodes"
		
	#make sure your run 'az login' and use WorkspaceOn SSO prior to running this
	
	az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION

	az aks create --name $cluster_name \
		--resource-group $AZURE_RESOURCE_GROUP \
		--kubernetes-version "1.22.6" \
		--node-count $number_of_nodes \
		--node-vm-size "Standard_DS3_v2" # 4 vCPU, 14GB memory, 28GB temp disk 

	az aks get-credentials --overwrite-existing --resource-group $AZURE_RESOURCE_GROUP --name $cluster_name

}

#delete-aks-cluster
delete-aks-cluster() {

	cluster_name=$1

	scripts/printmsg.sh "Starting deleting resources of AKS cluster $cluster_name"
	
	az aks delete --name $cluster_name --resource-group $AZURE_RESOURCE_GROUP --yes
}


#create-eks-cluster
create-eks-cluster () {

    #must run after setting access via 'aws configure'

    cluster_name=$1
	number_of_nodes=$2

	scripts/printmsg.sh "Creating EKS cluster $cluster_name with $number_of_nodes nodes"

    eksctl create cluster \
    --name $cluster_name \
    --nodegroup-name workers-$cluster_name \
    --version "1.21" \
    --region $AWS_REGION \
    --nodes $number_of_nodes \
	--set-kubeconfig-context \
    --node-type t3.xlarge # 4 vCPU , 16GB memory, 80GB temp disk 
	
    kubectl config rename-context $(kubectl config current-context) $cluster_name
}


#delete-eks-cluster
delete-eks-cluster () {

    cluster_name=$1

	scripts/printmsg.sh "Starting deleting resources of EKS cluster $cluster_name ..."
	
    eksctl delete cluster --name $cluster_name --force
}

#create-gke-cluster
create-gke-cluster () {

	cluster_name=$1
	number_of_nodes=$2

	scripts/printmsg.sh "Creating GKE cluster $cluster_name with $number_of_nodes nodes"
	
	gcloud container clusters create $cluster_name \
		--zone $GKE_ZONE \
		--project $GCP_PROJECT_ID \
		--num-nodes $number_of_nodes

	gcloud container clusters get-credentials $cluster_name --zone $GKE_ZONE --project $GCP_PROJECT_ID

	kubectl config rename-context $(kubectl config current-context) $cluster_name

}

#delete-eks-cluster
delete-gke-cluster () {

    cluster_name=$1

	scripts/printmsg.sh "Starting deleting resources of GKE cluster $cluster_name"
	
    gcloud container clusters delete $cluster_name \
		--zone $GKE_ZONE \
		--project $GCP_PROJECT_ID \
		--quiet

}

#create-minikube-cluster
create-minikube-cluster() {

	minikube start --cpus='8' --memory='10g' --kubernetes-version='1.22.6' --keep-context=true

	minikube tunnel

	kubectl config use-context minikube
}

#delete-minikube-cluster() {
delete-minikube-cluster() {
	
	minikube stop

}
#################### main #######################

#incorrect-usage
incorrect-usage() {
    echo
	echo "Incorrect usage. Please specify:"
    echo "  create [aks/eks/minikube cluster-name numbber-of-nodes]"
    echo "  delete [aks/eks/minikube cluster-name]"
    exit
}

case $1 in
create)
	case $2 in
	aks)
  		create-aks-cluster $3 $4
    	;;
	eks)
		create-eks-cluster $3 $4
		;;
	gke)
		create-gke-cluster $3 $4
		;;
	minikube)
		create-minikube-cluster $3 $4
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
delete)
    case $2 in
	aks)
  		delete-aks-cluster $3
    	;;
	eks)
		delete-eks-cluster $3
		;;
	gke)
		delete-gke-cluster $3
		;;
	minikube)
		delete-minikube-cluster $3
		;;
	*)
		incorrect-usage
		;;
	esac
	;;
*)
	incorrect-usage
	;;
esac