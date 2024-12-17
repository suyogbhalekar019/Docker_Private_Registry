#!/bin/bash

mkdir Registry

cd Registry

mkdir certs auth

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout certs/registry.key -out certs/registry.crt -subj "/CN=my-registry"

docker run --rm --entrypoint htpasswd httpd:2 -Bbn myuser mypasswd > auth/htpasswd

k create ns "docker-registry"

kubectl create secret tls docker-registry-tls-cert -n docker-registry --cert=/root/Registry/certs/registry.crt --key=/root/Registry/certs/registry.key

k create secret generic auth-secret --from-file=/root/Registry/auth/htpasswd -n "docker-registry"

mkdir volume

cat > volume.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: docker-registry-pv
  namespace: docker-registry
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteMany
  storageClassName: registry
  hostPath:
    path: "/root/Registry/volume/"

---

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: docker-registry-pvc
  namespace: docker-registry
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: registry
  resources:
    requests:
      storage: 1.5Gi
EOF

k apply -f volume.yaml

cat > deployment-yaml << EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: docker-registry
spec:
  replicas: 2
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
      - name: registry
        image: registry:2.8.2
        ports:
        - containerPort: 5015
        env:
        - name: REGISTRY_AUTH
          value: "/root/Registry/auth/htpasswd"
        - name: REGISTRY_AUTH_HTPASSWD_REALM
          value: "Registry Realm"
        - name: REGISTRY_HTTP_TLS_CERTIFICATE
          value: "/root/Registry/certs/registry.crt"
        - name: REGISTRY_HTTP_TLS_KEY
          value: "/root/Registry/certs/registry.key"
        volumeMounts:
        - name: lv-storage
          mountPath: /var/lib/registry
        - name: certs-vol
          mountPath: /root/Registry/certs
        - name: auth-vol
          mountPath: /root/Registry/auth
      volumes:
        - name: lv-storage
          persistentVolumeClaim:
            claimName: docker-registry-pvc
        - name: certs-vol
          secret:
            secretName: docker-registry-tls-cert
        - name: auth-vol
          secret:
            secretName: auth-secret
EOF

k apply -f deployment.yaml

cat > registry-svc.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: registry-service
  namespace: docker-registry
spec:
  selector:
    app: registry
  type: NodePort
  ports:
    - name: docker-port
      protocol: TCP
      port: 5015
      targetPort: 5015
      nodePort: 30222
EOF

k apply -f registry-svc.yaml

export REGISTRY_NAME="my-registry"

export REGISTRY_IP="Registry-svc-ip"

cat > /etc/hosts << EOF
Registry-svc-ip my-registry
EOF

echo "password" | scp -rv  /root/Registry/certs/registry.crt username@IP:/usr/local/share/ca-certificates/registry.crt

mkdir -p /etc/docker/certs.d/my-registry:30222

cp -v /root/Registry/certs/registry.crt  /etc/docker/certs.d/my-registry:30222

docker login my-registry:30222 -u myuser -p mypasswd

cat > /etc/docker/daemon.json << EOF
{
  "insecure-registries": ["my-registry:30222"]
}

EOF

sed -i '/[plugins."io.containerd.grpc.v1.cri".registry.mirrors]/a        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."my-registry:30222"]\n            endpoint = ["http://my-registry:30222"]' /etc/containerd/config.toml

systemctl restart containerd
