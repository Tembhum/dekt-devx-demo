#!/usr/bin/env bash

#################### load configs from values yaml  ################

    DEV_CLUSTER=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER=$(yq .prod-cluster.name .config/demo-values.yaml)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    PORTAL_DELIVERABLE="portal-prod-golden-config.yaml"
    SENSORS_DELIVERABLE="sensors-prod-golden-config.yaml"
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    APPS_NAMESPACE=$(yq .tap.appNamespace .config/demo-values.yaml)
    

#################### functions ################

    #dev-cluster
    dev-cluster() {

        echo
        echo "One API to install TAP on any kubectl:"
        echo
        echo "  tanzu package install tap"
        echo "      --package tap.tanzu.vmware.com"
        echo "      --version $TAP_VERSION"
        echo "      --values-file .config/tap_values.yaml"
        echo "      --namespace tap-install"
        echo
        echo "==========================================================="
        echo "TAP packages installed on $DEV_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $DEV_CLUSTER
        kubectl get nodes
        echo
        tanzu package installed list -n tap-install
    }

    #stage-cluster
    stage-cluster() {

        echo
        echo "==========================================================="
        echo "TAP packages installed on $STAGE_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $STAGE_CLUSTER
        kubectl get nodes
        echo
        tanzu package installed list -n tap-install
    }

    #prod-cluster
    prod-cluster() {
        
        echo
        echo "==========================================================="
        echo "TAP packages installed on $PROD_CLUSTER cluster ..."
        echo "==========================================================="
        echo
        kubectl config use-context $PROD_CLUSTER
        kubectl get nodes
        echo
        tanzu package installed list -n tap-install
    }

    #deploy-workloads
    deploy-workloads() {

        kubectl config use-context $DEV_CLUSTER

        echo
        echo "tanzu apps workload create -f ../mood-portal/workload.yaml -y -n $APPS_NAMESPACE"
        echo        
        tanzu apps workload create -f ../mood-portal/workload.yaml -y -n $APPS_NAMESPACE
        
        echo
        echo "tanzu apps workload create -f ../mood-sensors/workload.yaml -y -n $APPS_NAMESPACE"
        echo
        tanzu apps workload create -f ../mood-sensors/workload.yaml  -y -n $APPS_NAMESPACE
    }

    #promote-staging
    promote-staging() {

        kubectl config use-context $STAGE_CLUSTER
        
        tanzu apps workload create $PORTAL_WORKLOAD \
            --git-repo https://github.com/dektlong/mood-portal \
            --git-branch integrate \
            --type web \
            --label app.kubernetes.io/part-of=devx-mood \
            --yes \
            --namespace $APPS_NAMESPACE 
    }
  
    #promote-production
    promote-production () {

        kubectl config use-context $STAGE_CLUSTER

        echo
        echo "kubectl get deliverable $PORTAL_WORKLOAD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE"
        echo 
        kubectl get deliverable $PORTAL_WORKLOAD -n $APPS_NAMESPACE -oyaml > $PORTAL_DELIVERABLE
        echo "$PORTAL_DELIVERABLE generated."
        yq e 'del(.status)' $PORTAL_DELIVERABLE -i 
        yq e 'del(.metadata.ownerReferences)' $PORTAL_DELIVERABLE -i 

        echo
        echo "Hit any key to go production! ..."
        read

        kubectl config use-context $PROD_CLUSTER

        echo
        echo "kubectl apply -f $PORTAL_DELIVERABLE -n $APPS_NAMESPACE"
        echo 
        kubectl apply -f $PORTAL_DELIVERABLE -n $APPS_NAMESPACE

        kubectl get deliverables -n $APPS_NAMESPACE

    }

    
    #supplychains
    supplychains () {

        echo
        echo "tanzu apps cluster-supply-chain list"
        echo
        tanzu apps cluster-supply-chain list
    }

    #track-sensors
    track-sensors () {

        echo
        echo "tanzu apps workload get $SENSORS_WORKLOAD -n $APPS_NAMESPACE"
        echo
        tanzu apps workload get $SENSORS_WORKLOAD -n $APPS_NAMESPACE

    }

    #track-portal
    track-portal () {

        echo
        echo "tanzu apps workload get $PORTAL_WORKLOAD -n $APPS_NAMESPACE"
        echo
        tanzu apps workload get $PORTAL_WORKLOAD -n $APPS_NAMESPACE

    }    

    #tail-sensors-logs
    tail-sensors-logs () {

          tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE
    }

    #tail-portal-logs
    tail-portal-logs () {

        tanzu apps workload tail $PORTAL_WORKLOAD --since 100m --timestamp  -n $APPS_NAMESPACE

    }

    #scanning-results
    scanning-results () {

        kubectl describe imagescan.scanning.apps.tanzu.vmware.com/$SENSORS_WORKLOAD -n $APPS_NAMESPACE

    }
        

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $APPS_NAMESPACE -y

        kubectl config use-context $PROD_CLUSTER
        kubectl delete -f $PORTAL_DELIVERABLE

        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $PORTAL_WORKLOAD -n $APPS_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $APPS_NAMESPACE -y
        kubectl delete pod -l app=backstage -n tap-gui
        kubectl -n app-live-view delete pods -l=name=application-live-view-connector
        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-full.yaml

        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
    }

    #toggle the BYPASS_BACKEND flag in mood-portal
    toggle-dog () {

        pushd ../mood-portal

        case $1 in
        happy)
            sed -i '' 's/false/true/g' main.go
            git commit -a -m "always happy"      
            ;;
        sad)
            sed -i '' 's/true/false/g' main.go
            git commit -a -m "usually sad"
            ;;
        *)      
            echo "!!!incorrect-usage. please specify happy / sad"
            ;;
        esac
        
        git push
        pushd
    }

    #cleanup-helper
    cleanup-helper() {
        toggle-dog sad
        rm -f $PORTAL_DELIVERABLE
    }
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo
        echo "  dev-cluster"
        echo "  deploy-workloads"
        echo "  behappy"
        echo
        echo "  stage-cluster"
        echo "  promote-staging"
        echo
        echo "  prod-cluster"
        echo "  promote-production"
        echo
        echo "  supplychains"
        echo "  track-sensors"
        echo "  track-portal"
        echo "  tail-sensors-logs"
        echo "  tail-portal-logs"
        echo "  scanning-results"
        echo
        echo "  reset"
        exit
    }

#################### main ##########################

case $1 in
dev-cluster)
    dev-cluster
    ;;
stage-cluster)
    stage-cluster
    ;;
prod-cluster)
    prod-cluster
    ;;
deploy-workloads)
    deploy-workloads
    ;;
promote-staging)
    promote-staging
    ;;
promote-production)
    promote-production
    ;;
supplychains)
    supplychains
    ;;
track-sensors)
    track-sensors
    ;;
track-portal)
    track-portal
    ;;
tail-sensors-logs)
    tail-sensors-logs
    ;;
tail-portal-logs)
    tail-portal-logs
    ;;
scanning-results)
    scanning-results
    ;;
behappy)
    toggle-dog happy
    ;;
reset)
    reset
    ;;
cleanup-helper)
    cleanup-helper
    ;;
*)
    incorrect-usage
    ;;
esac
