1. Set default namespaces

```bash
kubectl config set-context $(kubectl config current-context) --namespace=mynamespace
```

2. Helpful aliases

```bash
alias k='kubectl'
alias kc='k config view --minify | grep name'
alias kdp='kubectl describe pod'
alias krh='kubectl run --help | more'
alias ugh='kubectl get --help | more'
alias c='clear'
alias kd='kubectl describe pod'
alias ke='kubectl explain'
alias kf='kubectl create -f'
alias kg='kubectl get pods --show-labels'
alias kr='kubectl replace -f'
alias kh='kubectl --help | more'
alias krh='kubectl run --help | more'
alias ks='kubectl get namespaces'
alias l='ls -lrt'
alias ll='vi ls -rt | tail -1'
alias kga='k get pod --all-namespaces'
alias kgaa='kubectl get all --show-labels'
```

3. Create YAML from kubectl commands

```bash
kubectl run busybox --image=busybox --dry-run=client -o yaml --restart=Never > yamlfile.yaml
kubectl create job my-job --dry-run=client -o yaml --image=busybox -- date  > yamlfile.yaml
kubectl run busybox --image=busybox --dry-run=client -o yaml --restart=Never -- /bin/sh -c "while true; do echo hello; echo hello again;done" > yamlfile.yaml
kubectl run wordpress --image=wordpress –-expose –-port=8989 --restart=Never -o yaml
```

4. Extend kubectl and create your own commands using raw outputs

```bash
kubectl get deployments -o json
kubectl get --raw=/apis/apps/v1/deployments
kubectl get --raw=/apis/apps/v1/deployments | jq '.items[] | {name: .metadata.name, replicas: .status.replicas, available: (.status.availableReplicas // 0), unavailable: (.status.unavailableReplicas // 0)} | select (.unavailable > 0)'
```

5. Inject an environment variable into deployment

```bash
kubectl set env deployment/registry STORAGE_DIR=/local
```
