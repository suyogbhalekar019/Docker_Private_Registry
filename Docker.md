# deploying a Private Docker Registry

mkdir Registry

cd Registry

mkdir certs auth

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout certs/registry.key -out certs/registry.crt -subj "/CN=my-registry" -addext "subjectAltName=DNS:my-registry"

docker run --entrypoint htpasswd httpd:2 -Bbn myuser mypasswd > auth/htpasswd

k create ns "docker-registry"

kubectl create secret tls docker-registry-tls-cert -n docker-registry --cert=/root/Registry/certs/registry.crt --key=/root/Registry/certs/registry.key

k get secret -n "docker-registry"

k describe secret docker-registry-tls-cert -n "docker-registry"

k create secret generic auth-secret --from-file=/root/Registry/auth/htpasswd -n "docker-registry"

k get secret -n "docker-registry"

k describe secret auth-secret -n "docker-registry"

mkdir volume

k apply -f deployment.yaml

k get po -n "docker-registry" -o wide

k apply -f registry-svc.yaml

k get svc -n docker-registry

k describe svc/registry-service -n docker-registry

export REGISTRY_NAME="my-registry"

export REGISTRY_IP="Registry-svc-ip"

vim /etc/hosts   (do this entry on all cluster nodes)

Registry-svc-ip my-registry

:wq

## Now try to login docker from any of the worker node

docker login my-registry:5015 -u myuser -p mypasswd     (It will thrown the error and to resolve this do the below steps)

cat /root/Registry/certs/registry.crt

## Copy the content and add in to the all nodes in below path

/usr/local/share/ca-certificates/registry.crt

## Now update the certificates on all nodes

sudo update-ca-certificates

## Then create the below file on all the servers and copy the same registry.crt content in it

mkdir -p /etc/docker/certs.d/my-registry:5015

cp -v /root/Registry/certs/registry.crt  /etc/docker/certs.d/my-registry:5015

## Now try to do login docker from any of the worker node

docker login my-registry:5015 -u myuser -p mypasswd

## Now just test the Registry is working fine or not

docker pull nginx

docker tag nginx:latest my-registry:5015/nginx:v2

docker push my-registry:5015/nginx:v2

## Now verified

k get po -n docker-registry

k exec -it registry-5486c865bd-qsj2j  --  sh

ls -lrth

cd /var/lib/registry

ls -lrth

exit

## Now just do the deployment by using this image which is pushed in registry

## Now create one more secrete for docker registry so while do the deployment it will authenticate that you are authenticate useer

kubectl create secret docker-registry nginx-secret --docker-server=my-registry:5015 --docker-username=myuser --docker-password=mypasswd

k apply -f  new.yaml

k get pods
