## Netshoot

a Docker + Kubernetes network trouble-shooting swiss-army container: https://github.com/nicolaka/netshoot

### For Container

1. Container’s Network Namespace: If you’re having networking issues with your application’s container, you can launch netshoot with that container’s network namespace like this:

```bash
docker run -it --net container:<container_name> nicolaka/netshoot
```

2. Host’s Network Namespace: If you think the networking issue is on the host itself, you can launch netshoot with that host’s network namespace:

```bash
docker run -it --net host nicolaka/netshoot
```

3. Network’s Network Namespace: If you want to troubleshoot a Docker network, you can enter the network’s namespace using nsenter. This is explained in the nsenter section below.

### For Kubernetes

1. If you want to spin up a throw away container for debugging.

```bash
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash
```

2. f you want to spin up a container on the host’s network namespace.

```bash
kubectl run tmp-shell --rm -i --tty --overrides='{"spec": {"hostNetwork": true}}' --image nicolaka/netshoot -- /bin/bash
```
