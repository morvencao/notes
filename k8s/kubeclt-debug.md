# Kubernetes Debug Best Practice

Debug kubernetes pod with ephemeral container.

## Why We Need Ephemeral Containers?

There are many scenarios in which we need an ephemeral debug container, such as:

1. Pod/Container is crashing, so it can't be attached to.
2. No debug utilities in pod/container, for example, the base image is [scratch](https://hub.docker.com/_/scratch) or [distroless](https://github.com/GoogleContainerTools/distroless).
3. `kubectl cp` is not easy to use and requires `tar` command in the target container.
4. SSH to cluster nodes is often forbidden, which means debugging on node(`kubectl debug node/mynode -it —image=ubuntu`) is not always possible.
5. Copy a pod for debugging will not reproduce the "SNAPSHOT" when the original issue was found.

## Core Idea

When we are in the scenarios mentioned above, it would be perfect to add a new container to the running pod without restarting it, such a new container could be used to inspect the other containers in the (acting up) pod regardless of their state and content. And this new added container is called ephemeral container. it is a temporary container that we may add to an existing Pod for user-initiated activities such as debugging. Ephemeral containers have no resource or scheduling guarantees, and they will not be restarted when they exit or when a Pod is removed or restarted. The [Ephemeral Container](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/) was graduated to beta and are now available by default in kubernetes 1.23 and above.

## Command: kubectl debug

Thanks to the [EphemeralContainer](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.19/#ephemeralcontainer-v1-core), we can add a new ephemeral container to running pod without restarting it. That’s how `kubectl debug` works in the background.

### Example Deployment for Debugging

Let’s create a basic deployment with distroless container:

```bash
# kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
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

# POD_NAME=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
```

Verify that no debug utilities in conatiner:

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

Now, we can attach to the debug container for debugging:

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

Let's list the processes from the new ephemeral container:

```bash
/ # ps auxf
PID   USER     TIME  COMMAND
    1 root      0:00 sh
   15 root      0:00 ps auxf
```

As you can see from output above, the processes in `app` container can't be listed from the ephemeral container. That's because PID namespace by default is not shared among containers in a pod. A solution from Kubernetes official [document](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/) is enabling the `shareProcessNamespace` in deployment:

```bash
kubectl patch deployment web --patch '{"spec": {"template": {"spec": {"shareProcessNamespace": true}}}}'
```

Then we list the processes from the new ephemeral container again:

```bash
# POD_NAME=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
# kubectl debug -it -c debugger --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}
/ # ps auxf
PID   USER     TIME  COMMAND
    1 65535     0:00 /pause
    8 root      0:00 python -m http.server 8080
   38 root      0:00 sh
   51 root      0:00 ps auxf
```

We can see the processes in other containers, but the pod is restarted after patching the original deployment for `shareProcessNamespace`:

```bash
# kubectl get rs
NAME              DESIRED   CURRENT   READY   AGE
web-5d5b5dd798   0         0         0       1m35s
web-6f49c6658f   1         1         1       27s
```

So, is there a better way?

Yes, `kubectl debug` provide `--target` argument to access target process, to make the target container and ephemeral container share the same PID namespace.

```bash
# kubectl debug --help
Debug cluster resources using interactive debugging containers.
...
  -i, --stdin=false: Keep stdin open on the container(s) in the pod, even if nothing is attached.
      --target='': When using an ephemeral container, target processes in this container name.
...
```

Let’s redeploy the `web` deployment and try to add new debug container with `--target` argument:

```bash
# kubectl delete deployment web
# kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
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

# POD_NAME=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
# kubectl debug -it -c debugger --target=app --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}
/ # ps auxf
PID   USER     TIME  COMMAND
    1 root      0:00 python -m http.server 8080
   14 root      0:00 sh
   26 root      0:00 ps auxf
```

As we can see from above output, the processes in `app` container can be listed from the ephemeral container.

### Before ending

`kubectl debug` command also provides `--copy-to` argument to let us create a new pod for debug but with some slight changes to pod/container spec, this is useful if we want to create a totally new debugging pod, for example:

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
