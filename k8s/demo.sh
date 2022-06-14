#!/bin/bash

########################
# include the magic
########################
. demo-magic.sh

clear

echo 'Create a kubernetes cluster >= 1.23, we use KinD cluster for this demo'
kind delete cluster --name test >> /dev/null 2>&1
kind create cluster --name test
docker pull busybox >> /dev/null 2>&1
kind load docker-image busybox --name test >> /dev/null 2>&1

echo 'Create a basic deployment with distroless container'
pe "cat app-web.yaml"
pe "kubectl apply -f app-web.yaml"

echo 'Retrieve the pod name for later usage'
pe "POD_NAME=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')"

echo 'Verify that no debug utilities in the app container'
pe "kubectl exec -it -c app ${POD_NAME} -- bash"
pe "kubectl exec -it -c app ${POD_NAME} -- ls"

echo 'Add an ephemeral debug container to the running pod'
pe "kubectl debug -it --attach=false -c debugger --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}"

echo 'Check the new ephemeral container'
pe "kubectl get pod ${POD_NAME} -o jsonpath='{.spec.ephemeralContainers}' | jq"
pe "kubectl get pod ${POD_NAME} -o jsonpath='{.status.ephemeralContainerStatuses}' | jq"

echo 'Now, we can execute command in the debug container'
pe "kubectl exec -it -c debugger ${POD_NAME} -- wget -O - localhost:8080"

echo "Let's list the processes in the pod"
pe "kubectl exec -it -c debugger ${POD_NAME} -- ps auxf"

echo "As we can see from output, the processes in other containers can't be listed from the ephemeral container."
echo "That's because PID namespace by default is not shared among containers."

echo 'Add another ephemeral debug container that shares PID namespace with target container to the running pod'
pe "kubectl debug -it --attach=false -c debugger2 --target=app --image=busybox --image-pull-policy=IfNotPresent ${POD_NAME}"

"echo 'Then, list the processes from the new ephemeral container'"
pe "kubectl exec -it -c debugger2 ${POD_NAME} -- ps auxf"

echo 'We can also create a copy of the running pod to test-pod and add an ephemeral container to share processes'
pe "kubectl debug -it --attach=false -c debugger --image=busybox --image-pull-policy=IfNotPresent --copy-to test-pod --share-processes ${POD_NAME}"
pe "kubectl exec -it -c debugger test-pod -- ps auxf"

kind delete cluster --name test >> /dev/null 2>&1
