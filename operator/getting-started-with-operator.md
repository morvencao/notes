## Overview

Operator is a method of packaging, deploying and managing a kubernetes application. In other words Day-1(install) + Day-2 (management/upgrade/uninstall...) operatoions. In comparison to Helm, Helm was focussed on Day 1. Helm provided a well defined packaging of Kubernetes application, whereas operators bring in both Day-1 and Day-2 operations together. Operators are most suited for complex and stateful applications requiring application domain knowledge to correctly scale, upgrade, and reconfigure while protecting against data loss or unavailability.

## Operator SDK

### What is Operator SDK?

Operator SDK is component of the [Operator Framework](https://github.com/operator-framework), an open source toolkit to manage Kubernetes native applications, called Operators, in an effective, automated, and scalable way. The Operator SDK makes it easier to build Kubernetes native applications, a process that can require deep, application-specific operational knowledge.

### What can I do with Operator SDK?

The Operator SDK provides the tools to build, test, and package Operators. Initially, the SDK facilitates the marriage of an application’s business logic (for example, how to scale, upgrade, or backup) with the Kubernetes API to execute those operations. Over time, the SDK can allow engineers to make applications smarter and have the user experience of cloud services. Leading practices and code patterns that are shared across Operators are included in the SDK to help prevent reinventing the wheel.

The Operator SDK is a framework that uses the [controller-runtime](https://github.com/kubernetes-sigs/controller-runtime) library to make writing operators easier by providing:

1. High level APIs and abstractions to write the operational logic more intuitively
2. Tools for scaffolding and code generation to bootstrap a new project fast
3. Extensions to cover common Operator use cases


### Build an operator with Operator SDK?

**Note:** All the examples in the doc is built with Operator SDK `v0.18.0`.

#### Helm Operator

Here are some details for how to build a helm operator https://sdk.operatorframework.io/docs/building-operators/helm/quickstart/

##### Build a helm-based operator project

We can use one command to create a new Helm-based nginx-operator project:

```
operator-sdk new nginx-operator --api-version=example.com/v1alpha1 --kind=Nginx --type=helm
```

This creates the `nginx-operator` project specifically for watching the `Nginx` resource with APIVersion `example.com/v1alpha1` and Kind `Nginx`.

```
# tree nginx-operator/
nginx-operator/
├── build
│   └── Dockerfile
├── deploy
│   ├── crds
│   │   ├── example.com_nginxes_crd.yaml
│   │   └── example.com_v1alpha1_nginx_cr.yaml
│   ├── operator.yaml
│   ├── role.yaml
│   ├── role_binding.yaml
│   └── service_account.yaml
├── helm-charts
│   └── nginx
│       ├── Chart.yaml
│       ├── charts
│       ├── templates
│       │   ├── NOTES.txt
│       │   ├── _helpers.tpl
│       │   ├── deployment.yaml
│       │   ├── hpa.yaml
│       │   ├── ingress.yaml
│       │   ├── service.yaml
│       │   ├── serviceaccount.yaml
│       │   └── tests
│       │       └── test-connection.yaml
│       └── values.yaml
└── watches.yaml
```

**Note:** Instead of creating your project with a boilerplate Helm chart, you can also use `--helm-chart`, `--helm-chart-repo`, and `--helm-chart-version` to use an existing chart, either from your local filesystem or a remote chart repository.

##### Build and run a helm-based operator

1. Deploy the CRD:

```
kubectl create -f deploy/crds/example.com_nginxes_crd.yaml
```

2. Run as a pod inside a Kubernetes cluster:

```
operator-sdk build quay.io/morvencao/nginx-operator:v0.0.1
docker push quay.io/morvencao/nginx-operator:v0.0.1
sed -i 's|REPLACE_IMAGE|quay.io/morvencao/nginx-operator:v0.0.1|g' deploy/operator.yaml
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml
kubectl create -f deploy/operator.yaml
```

3. Deploy the Nginx custom resource:

```
kubectl apply -f deploy/crds/example.com_v1alpha1_nginx_cr.yaml
```

**Note:** The problem for helm operator is that developers can not customize the logic of the operator, it still using `helm/tiller` to manage charts.

#### Go Operator

Use Operator SDK to build your own operator, the major logic is building your own API(CRD) and your own `reconcile` method.

Developers can put their own logic in the go operator. Here are some details for how to use Go operator https://sdk.operatorframework.io/docs/building-operators/golang/quickstart/

##### Create a go-based operator project

1. We can use one command to create a new go-based memcached-operator project:

```
operator-sdk new memcached-operator --repo=github.com/example-inc/memcached-operator
cd memcached-operator
```

**Note:** operator-sdk new generates a `go.mod` file to be used with [Go modules](https://github.com/golang/go/wiki/Modules). The `--repo=<path>` flag is required when creating a project outside of `$GOPATH/src`, as scaffolded files require a valid module path. Ensure you activate module support before using the SDK.

2. Add a new Custom Resource Definition:

Add a new Custom Resource Definition(CRD) API called Memcached, with APIVersion `cache.example.com/v1alpha1` and Kind `Memcached`.

```
operator-sdk add api --api-version=cache.example.com/v1alpha1 --kind=Memcached
```

This will scaffold the Memcached resource API under `pkg/apis/cache/v1alpha1/....`

3. Define the spec and status:

Modify the `spec` and `status` of the `Memcached` Custom Resource(CR) at `pkg/apis/cache/v1alpha1/memcached_types.go`:

```
type MemcachedSpec struct {
	// Size is the size of the memcached deployment
	Size int32 `json:"size"`
}
type MemcachedStatus struct {
	// Nodes are the names of the memcached pods
	Nodes []string `json:"nodes"`
}
```

After modifying the `*_types.go` file always run the following command to update the generated code for that resource type:

```
operator-sdk generate k8s
```

4. Updating CRD manifests:

Now that `MemcachedSpec` and `MemcachedStatus` have fields and possibly annotations, the CRD corresponding to the API’s group and kind must be updated. To do so, run the following command:

```
operator-sdk generate crds
```

**Notes:** Your CRD must specify exactly one [storage version](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/#writing-reading-and-updating-versioned-customresourcedefinition-objects). Use the `+kubebuilder:storageversion` [marker](https://book.kubebuilder.io/reference/markers/crd.html) to indicate the GVK that should be used to store data by the API server. This marker should be in a comment above your Memcached type.

5. OpenAPI validation:

OpenAPIv3 schemas are added to CRD manifests in the `spec.validation` block when the manifests are generated. This validation block allows Kubernetes to validate the properties in a Memcached Custom Resource when it is created or updated.

Markers (annotations) are available to configure validations for your API. These markers will always have a `+kubebuilder:validation prefix`. For example, adding an enum type specification can be done by adding the following marker:

```
// +kubebuilder:validation:Enum=Lion;Wolf;Dragon
type Alias string
```

**Note:** A full list of OpenAPIv3 validation markers can be found [here](https://book.kubebuilder.io/reference/markers/crd.html).

To update the CRD `deploy/crds/cache.example.com_memcacheds_crd.yaml`, run the following command:

```
operator-sdk generate crds
```


An example of the generated YAML is as follows:

```
spec:
  validation:
    openAPIV3Schema:
      properties:
        spec:
          properties:
            size:
              format: int32
              type: integer
```

To learn more about OpenAPI v3.0 validation schemas in Custom Resource Definitions, refer to the [Kubernetes Documentation](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#specifying-a-structural-schema).

6. Add a new Controller:

Add a new [Controller](https://godoc.org/github.com/kubernetes-sigs/controller-runtime/pkg#hdr-Controller) to the project that will watch and reconcile the Memcached resource:

```
operator-sdk add controller --api-version=cache.example.com/v1alpha1 --kind=Memcached
```

This will scaffold a new Controller implementation under `pkg/controller/memcached/....`

For this example replace the generated Controller file `pkg/controller/memcached/memcached_controller.go` with the example [memcached_controller.go](https://github.com/operator-framework/operator-sdk/blob/v0.18.2/example/memcached-operator/memcached_controller.go.tmpl) implementation.

The example Controller executes the following reconciliation logic for each `Memcached` CR:

- Create a memcached Deployment if it doesn’t exist
- Ensure that the Deployment size is the same as specified by the `Memcached` CR spec
- Update the `Memcached` CR status using the status writer with the names of the memcached pods

##### Build and run a go-based operator

1. Before running the operator, the CRD must be registered with the Kubernetes apiserver:

```
kubectl create -f deploy/crds/cache.example.com_memcacheds_crd.yaml
```

2. Run as a Deployment inside the cluster:

Build the memcached-operator image and push it to a registry. Make sure to modify `quay.io/morvencao/` in the example below to reference a container repository that you have access to. You can obtain an account for storing containers at repository sites such quay.io or hub.docker.com:

```
operator-sdk build quay.io/morvencao/memcached-operator:v0.0.1
sed -i 's|REPLACE_IMAGE|quay.io/morvencao/memcached-operator:v0.0.1|g' deploy/operator.yaml
docker push quay.io/morvencao/memcached-operator:v0.0.1
```

The Deployment manifest is generated at `deploy/operator.yaml`. Be sure to update the deployment image as shown above since the default is just a placeholder.

Setup RBAC and deploy the memcached-operator:

```
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml
kubectl create -f deploy/operator.yaml
```

3. Create a `Memcached` CR:

Create the example `Memcached` CR that was generated at `deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml`:

```
cat deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml
apiVersion: "cache.example.com/v1alpha1"
kind: "Memcached"
metadata:
  name: "example-memcached"
spec:
  size: 3

kubectl apply -f deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml
```

**Update the size:**

```
cat deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml
apiVersion: "cache.example.com/v1alpha1"
kind: "Memcached"
metadata:
  name: "example-memcached"
spec:
  size: 4

kubectl apply -f deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml
```

##### Cleanup

Clean up the resources:

```
kubectl delete -f deploy/crds/cache.example.com_v1alpha1_memcached_cr.yaml
kubectl delete -f deploy/operator.yaml
kubectl delete -f deploy/role_binding.yaml
kubectl delete -f deploy/role.yaml
kubectl delete -f deploy/service_account.yaml
```

##### Advanced Topics

- [Manage CR status conditions](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#manage-cr-status-conditions)
- [Adding 3rd Party Resources To Your Operator](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#manage-cr-status-conditions)
- [Register with the Manager’s scheme](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#register-with-the-managers-scheme)
- [Handle Cleanup on Deletion](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#handle-cleanup-on-deletion)
- [Metrics](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#metrics)
- [Leader election](https://v0-18-x.sdk.operatorframework.io/docs/golang/quickstart/#leader-election)

**Note:** Prefer Go Operator because we have more control what the operator do and the order doing things.

#### Best Practise

- How to handle the case if your operator need to manage multiple resources?

  - Please refer to https://github.com/operator-framework/operator-sdk/issues/2300 for more detail.

  - Assume I have an application a1 which include c1, c2 and c3 as internal components, and now I want to create a operator to manage a1. Currently there here are two options for the operator of a1:

  - **Option 1**: Use one operator to manage c1, c2 and c3 for application a1.

  - **Option 2**: Build operators for c1, c2 and c3, then use build operator for application a1 with operators for c1, c2 and c3.

  - The best practise for this is it depends on the complexity of c1, c2, and c3. If they are simple components that are tightly coupled, then a single operator can handle all three.

  - However if one or more of them have complex reconciliation requirements (e.g. a database that requires backups and data migrations between versions) or they can be managed as standalone components (i.e. they have loose coupling), then separate operators for c1, c2, and c3 might make more sense. Then the a1 operator would only need to be concerned with the high-level abstractions exposed by the CRDs of c1, c2, and c3 operators.

- Each operator belong to different namespaces.
- Each operator should use [OLM(Operator Lifecycle Manager)](https://github.com/operator-framework/operator-lifecycle-manager) to manage its lifecycle.

### OLM(Operator Lifecycle Manager)

The Operator Lifecycle Manager (OLM) helps users install, update, and manage the lifecycle of all Operators and their associated services running across their clusters. It is part of the Operator Framework, an open source toolkit designed to manage Kubernetes native applications (Operators) in an effective, automated, and scalable way.

![OLM Lifecycle](./images/olm.png)

From above diagram, we can see that we need provide the operator and operator repo out of cluster. once we prepare them, we can use the operator in cluster. Firstly, we need to create a `OperatorSource` which is used to point to the operator repo. Secondly, we need to create `Subscription` to be used to keep your CSV up to date. Thirdly, create `OperatorGroup` to be used to by CSV and operator. Finally, you can create a CR to consume your CRD.

## References

- https://coreos.com/blog/introducing-operator-framework
- https://sdk.operatorframework.io
- https://github.com/operator-framework/getting-started#getting-started
- https://github.com/operator-framework/operator-lifecycle-manager
- https://github.com/operator-framework/operator-registry
- https://docs.openshift.com/container-platform/4.5/operators/olm-what-operators-are.html

