# Observability with Envoy ALS using Upstream Skywalking

#### Deployment Architecture

The object of this is to demonstrate Observability of your applications using upstream Skywalking. We demonstrate this on GCP project that has Traffic Director enabled. We deploy skywalking in _skywalking_ namespace bookinfo in _bookinfo_ namespace.

![Alt text](deployment.jpg?raw=true "Title")

#### Deployment Steps

Deployment involves 3 steps:

1. Preparing Google Traffic Director on your GCP project
2. Deploying upstream Apache Skywalking, Elasticsearch onto GKE cluster
3. Deploying bookinfo app onto GKE cluster

#### Preparing Google Traffic Director on your GCP Project

Ensure your project has Google Traffic Director enabled, along with full API access.

Prepare Google Traffic Director onto your GCP project to load balance backend services. This will also ensure all Envoy sidecars and gateways communicate with Traffic Director xDS service. Follow the instructions in [Preparing for Traffic Director setup](https://cloud.google.com/traffic-director/docs/setting-up-traffic-director).

Alternatively, we supplied a script that you can run on your project. If you are doing so, please ensure the variable declarations match that of your environment.

```bash
./setup_traffic_director.sh
```

#### Deploying upstream Apache Skywalking onto GKE Cluster

Deploy elasticsearch for Skywalking in the same cluster.

```bash
kubectl create namespace skywalking
```

```bash
kubectl apply -n skywalking -f elasticsearch.yaml
```

Deploy SW on K8s cluster. See [Deploy backend in kubernetes](https://github.com/apache/skywalking/blob/master/docs/en/setup/backend/backend-k8s.md) for details. Follow instructions to generate Skywalking 6.4.0 YAML.

```bash
git clone https://github.com/apache/skywalking-kubernetes.git
cd skywalking-kubernetes/helm-chart/helm3/6.4.0
helm dep up skywalking
helm template --name skywalking skywalking > sw.yaml
kubectl apply -n skywalking -f sw.yaml
```

Kubernetes `ClusterRole` & `ClusterRoleBinding` must be properly initialized for the appropriate OAP ServiceAccount. For convenience, we have supplied a Skywalking YAML generated off of the upstream Skywalking 6.4.0 that includes Kubernetes RBAC.

```bash
kubectl apply -n skywalking -f skywalking.yaml
```

#### Deploying bookinfo app onto GKE Cluster

Prepare your Kubernetes application namespace.

```bash
kubectl create namespace bookinfo
```

Obtain a copy of `bookinfo.yaml` or any other app without sidecar.

We have provided bookinfo YAMLs here, split them into `bookinfo-productpage.yaml` and `bookinfo-others.yaml`. The minor difference (w.r.t. upstream bookinfo) is due to the need for sidecar injection differently onto these apps, exposing productpage as LoadBalancer instead of ClusterIP. We chose manual injection because of minor sidecar parameter differences to stream Envoy ALS. Both apps are to be deployed in the same namespace.

Follow these steps to deploy the app onto your GKE cluster.

First, apply Kubernetes ConfigMap for custom bootstrap Envoy config. The injection templates are different for productpage and others, and hence the need for two ConfigMaps.

```bash
kubectl apply -n bookinfo -f custom-bootstrap-productpage.yaml
kubectl apply -n bookinfo -f custom-bootstrap-others.yaml
```

Next, inject productpage sidecar manually using `istioctl`.

For convenience, the repository also includes sidecar-injected apps, so you could apply directly.

```bash
istioctl kube-inject --injectConfigFile inject-config-productpage.yaml \
    --meshConfigFile mesh-config.yaml \
    --valuesFile inject-values.yaml \
    -f bookinfo-productpage.yaml > bookinfo-productpage-sidecar.yaml
```

Next, inject other app sidecar manually using `istioctl`.

```bash
istioctl kube-inject --injectConfigFile inject-config-others.yaml \
    --meshConfigFile mesh-config.yaml \
    --valuesFile inject-values.yaml \
    -f bookinfo-others.yaml > bookinfo-others-sidecar.yaml
```

Create apps with sidecar onto GKE cluster.

```bash
kubectl apply -n bookinfo -f bookinfo-productpage-sidecar.yaml
kubectl apply -n bookinfo -f bookinfo-others-sidecar.yaml
```

Generate traffic.

Obtain productpage external loadbalancer IP.

```bash
LB=$(k get services --namespace bookinfo productpage --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -v http://${LB}:8443/productpage
```

Verify results on Skywalking UI using browser.

```bash
open $(k get services --namespace skywalking skywalking-skywalking-ui --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

#### References

- [Preparing for Traffic Director setup](https://cloud.google.com/traffic-director/docs/setting-up-traffic-director)
- [GCP Envoy bootstrap configuration](https://github.com/istio/istio/blob/master/install/gcp/bootstrap/gcp_envoy_bootstrap.json)
- [GCP Envoy Bootstrap configuration](https://github.com/istio/istio/blob/master/samples/custom-bootstrap/README.md)
- [Deploy backend in kubernetes](https://github.com/apache/skywalking/blob/master/docs/en/setup/backend/backend-k8s.md)
