#!/usr/bin/env bash

#
# Setting up Google Traffic Directon on GKE
#
# Reference:
# https://cloud.google.com/traffic-director/docs/set-up-gke-pods
#

#
# Note: assumed backend services are annotated with NEGs
# See Configuring GKE / Kubernetes services with NEGs in above link for details
# metadata:
#  annotations:
#      cloud.google.com/neg: '{"exposed_ports":{"80":{}}}'
#
# Verify using:
# gcloud beta compute network-endpoint-groups list
#

export PREFIX="td"

# to be on par with TD gcloud CLI expectations
gcloud components update

# obtain creds
PROJECT=my-cool-project
CLUSTER=cluster-2
REGION=us-central1
ZONE=us-central1-a
gcloud container clusters get-credentials ${CLUSTER} --region ${REGION} --project ${PROJECT}

# add iam auth to service account
PROJECT=$(gcloud config get-value project)
SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list \
		--format='value(email)' \
		--filter='displayName:Compute Engine default service account')

gcloud projects add-iam-policy-binding ${PROJECT} \
	--member serviceAccount:${SERVICE_ACCOUNT_EMAIL} \
	--role roles/compute.networkViewer

# health check
gcloud compute health-checks create http $(PREFIX)-gke-health-check --use-serving-port

# backend service
gcloud compute backend-services create $(PREFIX)-gke-service --global \
	--health-checks $(PREFIX)-gke-health-check \
	--load-balancing-scheme INTERNAL_SELF_MANAGED

# Add NEG to backend service
NEG_NAME=$(gcloud beta compute network-endpoint-groups list | grep ${ZONE} | tail -1 | tr -s     " " | cut -d " " -f 1)

gcloud compute backend-services add-backend $(PREFIX)-gke-service \
    --global \
    --network-endpoint-group ${NEG_NAME} \
    --network-endpoint-group-zone ${ZONE} \
    --balancing-mode RATE \
    --max-rate-per-endpoint 5

# create route rule
gcloud compute url-maps create $(PREFIX)-gke-url-map \
	--default-service $(PREFIX)-gke-service

gcloud compute url-maps add-path-matcher $(PREFIX)-gke-url-map \
	--default-service $(PREFIX)-gke-service \
	--path-matcher-name $(PREFIX)-gke-path-matcher

gcloud compute url-maps add-host-rule $(PREFIX)-gke-url-map \
	--hosts productpage \
	--path-matcher-name $(PREFIX)-gke-path-matcher

gcloud compute target-http-proxies create $(PREFIX)-gke-proxy \
		--url-map $(PREFIX)-gke-url-map

PORT=9080
gcloud compute forwarding-rules create $(PREFIX)-gke-forwarding-rule \
	--global \
	--load-balancing-scheme=INTERNAL_SELF_MANAGED \
	--address=0.0.0.0 \
	--target-http-proxy=$(PREFIX)-gke-proxy \
  --ports ${PORT} --network default
