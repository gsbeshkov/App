#!/bin/sh
set -e

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

CURRENT_USER=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.MONGO_USER}' | base64 -d)
if [ "$CURRENT_USER" = "proxyUser1" ]; then
  NEXT_USER="proxyUser2"
else
  NEXT_USER="proxyUser1"
fi

NEW_PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32)

NEXT_USER_LOWER=$(echo "$NEXT_USER" | tr '[:upper:]' '[:lower:]')
CURRENT_USER_LOWER=$(echo "$CURRENT_USER" | tr '[:upper:]' '[:lower:]')

kubectl run mongo-rotate-$NEXT_USER_LOWER \
  --image=mongo:latest \
  --restart=Never \
  --rm \
  --attach \
  -n "$NAMESPACE" \
  --env="MONGO_HOST=$MONGO_HOST" \
  --env="MONGO_ADMIN_USER=$MONGO_ADMIN_USER" \
  --env="MONGO_ADMIN_PASSWORD=$MONGO_ADMIN_PASSWORD" \
  --env="NEXT_USER=$NEXT_USER" \
  --env="NEW_PASSWORD=$NEW_PASSWORD" \
  --env="MONGO_DB=$MONGO_DB" \
  -- mongosh "mongodb://$MONGO_ADMIN_USER:$MONGO_ADMIN_PASSWORD@$MONGO_HOST/admin" \
     --eval '
       const admin = db.getSiblingDB("admin");
       if (admin.getUser(process.env.NEXT_USER) === null) {
         admin.createUser({ user: process.env.NEXT_USER, pwd: process.env.NEW_PASSWORD, roles: [{ role: "readWrite", db: process.env.MONGO_DB }] });
       } else {
         admin.updateUser(process.env.NEXT_USER, { pwd: process.env.NEW_PASSWORD });
       }
     '

kubectl patch secret "$SECRET_NAME" -n "$NAMESPACE" \
  --type='json' \
  -p="[
    {\"op\": \"replace\", \"path\": \"/data/MONGO_USER\", \"value\": \"$(printf '%s' $NEXT_USER | base64 -w0)\"},
    {\"op\": \"replace\", \"path\": \"/data/MONGO_PASSWORD\", \"value\": \"$(printf '%s' $NEW_PASSWORD | base64 -w0)\"}
  ]"

kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout=120s

kubectl run mongo-delete-$CURRENT_USER_LOWER \
  --image=mongo:latest \
  --restart=Never \
  --rm \
  --attach \
  -n "$NAMESPACE" \
  --env="MONGO_ADMIN_USER=$MONGO_ADMIN_USER" \
  --env="MONGO_ADMIN_PASSWORD=$MONGO_ADMIN_PASSWORD" \
  --env="MONGO_HOST=$MONGO_HOST" \
  --env="CURRENT_USER=$CURRENT_USER" \
  -- mongosh "mongodb://$MONGO_ADMIN_USER:$MONGO_ADMIN_PASSWORD@$MONGO_HOST/admin" \
     --eval 'db.getSiblingDB("admin").dropUser(process.env.CURRENT_USER)'
