# Kubernetes Debug Best Practice

Debug in Kubernetes cluster with ephemeral container.

## Why We Need Ephemeral Container?

1. Can't accach to it because pod/container is crashing.
2. No debug utilities, because container base image is [scratch](https://hub.docker.com/_/scratch) or [distroless](https://github.com/GoogleContainerTools/distroless).
3. `kubectl cp` is not easy to use and requires tar.
4. SSH to cluster nodes is often forbidden, so debug on node(`kubectl debug node/mynode -it —image=ubuntu
`) will not be possible.
5. Copy a pod for debugging will not reproduce the "SNAPSHOT" when the issue is found.

## Core Idea

Add a new container to an already running pod without restarting it, such a new container could be used to inspect the other containers in the (acting up) pod regardless of their state and content.

This is the document of an [Ephemeral Container](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/) as Kubernetes 1.23 beta feature.

## Command: kubectl debug

Thanks to the [EphemeralContainer](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.19/#ephemeralcontainer-v1-core), we can add a new ephemeral container to running pod without restarting it. That’s how `kubectl debug` works in the background. (>=k8s 1.23)

### Example

Let’s create a basic deployment with a distroless container:

```bash
$ kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slim
spec:
  selector:
    matchLabels:
      app: slim
  template:
    metadata:
      labels:
        app: slim
    spec:
      containers:
      - name: app
        image: gcr.io/distroless/python3-debian11
        command:
        - python
        - -m
        - http.server
        - '8080'
EOF

$ POD_NAME=$(kubectl get pods -l app=slim -o jsonpath='{.items[0].metadata.name}')
```

Verify that no debug utilities in conatiners:

```bash
# kubectl exec -it -c app ${POD_NAME} -- bash
error: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "a51bbbff45de77d560ef9af045861685e0e518757cdcf0cab5ea1cf8ea91f5a2": OCI runtime exec failed: exec failed: container_linux.go:380: starting container process caused: exec: "bash": executable file not found in $PATH: unknown
# kubectl exec -it -c app ${POD_NAME} -- sh
# ls
sh: 1: ls: not found
```

## Inspecting Pod With Ephemeral Container:

Add an ephemeral debug container to the running pod:

```bash
kubectl debug -it --attach=false -c debugger --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}
```

Check the new ephemeral container:

```bash
# kubectl get pod ${POD_NAME} -o jsonpath='{.spec.ephemeralContainers}' | jq
[
  {
    "image": "busybox",
    "imagePullPolicy": "IfNotPresent",
    "name": "debugger",
    "resources": {},
    "stdin": true,
    "terminationMessagePath": "/dev/termination-log",
    "terminationMessagePolicy": "File",
    "tty": true
  }
]

# kubectl get pod ${POD_NAME} -o jsonpath='{.status.ephemeralContainerStatuses}' | jq
[
  {
    "containerID": "containerd://1842853885ec39ca86c7c357010b283cb36c589e1b23c6e779afc7ef00238cc7",
    "image": "docker.io/library/busybox:latest",
    "imageID": "sha256:62aedd01bd8520c43d06b09f7a0f67ba9720bdc04631a8242c65ea995f3ecac8",
    "lastState": {},
    "name": "debugger",
    "ready": false,
    "restartCount": 0,
    "state": {
      "running": {
        "startedAt": "2022-06-13T06:30:47Z"
      }
    }
  }
]
```

Attch to the debug container:

```bash
# kubectl attach -it -c debugger ${POD_NAME}
/ # wget -O - localhost:8080
Connecting to localhost:8080 (127.0.0.1:8080)
writing to stdout
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Directory listing for /</title>
</head>
<body>
...
-                    100% |********************************************************************************************************************************************************************************************|   904  0:00:00 ETA
written to stdout
```

### How About Process?

Check the proxess from the new ephemeral container:

```bash
/ # ps auxf
PID   USER     TIME  COMMAND
    1 root      0:00 sh
   15 root      0:00 ps auxf
```

We can't see the proxess in other containers, because PID namespace by default is not shared among contains in a pod. A solution from Kubernetes official [document](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/) is enabling the `shareProcessNamespace` in deployment:

```bash
kubectl patch deployment slim --patch '
spec:
  template:
    spec:
      shareProcessNamespace: true'
```

Check the process from the new ephemeral container again:

```bash
# POD_NAME=$(kubectl get pods -l app=slim -o jsonpath='{.items[0].metadata.name}')
# kubectl debug -it -c debugger --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}
/ # ps auxf
PID   USER     TIME  COMMAND
    1 65535     0:00 /pause
    8 root      0:00 python -m http.server 8080
   38 root      0:00 sh
   51 root      0:00 ps auxf
```

But, the pod is restarted after pctching the original deployment for `shareProcessNamespace`:

```bash
# kubectl get rs
NAME              DESIRED   CURRENT   READY   AGE
slim-5d5b5dd798   0         0         0       4m35s
slim-6f49c6658f   1         1         1       3m57s
```

Is there a better way?

Yes, `kubectl debug` provide `--target` argument to access target process:

```bash
# kubectl debug --help
Debug cluster resources using interactive debugging containers.
...
  -i, --stdin=false: Keep stdin open on the container(s) in the pod, even if nothing is attached.
      --target='': When using an ephemeral container, target processes in this container name.
...
```

Let’s delete `slim` deployment and try again with `--target`

```bash
$ kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slim
spec:
  selector:
    matchLabels:
      app: slim
  template:
    metadata:
      labels:
        app: slim
    spec:
      containers:
      - name: app
        image: gcr.io/distroless/python3-debian11
        command:
        - python
        - -m
        - http.server
        - '8080'
EOF

$ POD_NAME=$(kubectl get pods -l app=slim -o jsonpath='{.items[0].metadata.name}')
```

Try again with `--target` argument:

```bash
# POD_NAME=$(kubectl get pods -l app=slim -o jsonpath='{.items[0].metadata.name}')
# kubectl debug -it -c debugger --target=app --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}
/ # ps auxf
PID   USER     TIME  COMMAND
    1 root      0:00 python -m http.server 8080
   14 root      0:00 sh
   26 root      0:00 ps auxf
```

### Before ending

`kubectl debug` command also provides `--copy-to` argument to let us create a new pod for debug but with some slight changes to pod/container spec, this is useful if we want to create a totally new debug pod:

```bash
# kubectl debug -it -c debugger --image=busybox --image-pull-policy=IfNotPresent \
  --copy-to test-pod \
  --share-processes \
  ${POD_NAME}
/ # ps auxf
PID   USER     TIME  COMMAND
    1 65535     0:00 /pause
    7 root      0:00 python -m http.server 8080
   37 root      0:00 sh
   49 root      0:00 ps auxf
```
