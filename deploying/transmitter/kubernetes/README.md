# IBM Verify Antenna Transmitter Kubernetes Deployment Guide

This guide walks you through deploying an IBM Verify Antenna Transmitter on a Kubernetes cluster.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
  - [Generating Keys and Certificates](#generating-keys-and-certificates)
  - [Creating Transformation Handlers](#creating-transformation-handlers)
  - [Configuring Authorization Scheme](#configuring-authorization-scheme)
  - [Creating ConfigMaps and Secrets](#creating-configmaps-and-secrets)
- [Deploying to Kubernetes](#deploying-to-kubernetes)
- [Verifying the Deployment](#verifying-the-deployment)
- [Troubleshooting](#troubleshooting)

## Overview

The IBM Verify Antenna Transmitter ingests raw security events, transforms them into SSF-compliant events, and transmits them to SSF receivers.

> 📘 Note
>
> Transformation handlers determine Antenna's resource requirements. Complex handlers can impact processing rates.
> Simple object-to-object mapping is the recommended approach. Avoid augmenting events by calling external sources.

## Prerequisites

### Required Tools

- **kubectl**: Kubernetes command-line tool (v1.20+)
- **openssl**: For generating SSL/TLS certificates

### Kubernetes Cluster

- **Kubernetes version**: 1.20 or higher
- **Storage**: Dynamic volume provisioning or pre-created PersistentVolumes
- **Resources**: Minimum 2 CPU cores and 4GB RAM available
- **Access**: Cluster admin permissions for creating resources

### IBM Verify Tenant

- Sign up for a free trial at [ibm.biz/verify-trial](https://ibm.biz/verify-trial)
- This will be referenced as `tenant.verify.ibm.com` in configuration files

### Prerequisites Deployment

- **Datastore**: PostgreSQL and Kafka must be deployed first. Follow the [Datastore Deployment Guide](../datastore/README.md).

## Configuration

### Setting Up the Local Directory

> 📘 Note
>
> Perform these steps only if you haven't cloned this GitHub repository to your local system.

Build a directory structure matching the [configs](./configs) layout:

1. Create a directory named `antenna-transmitter` on your system and copy the contents of the [configs](./configs) directory into it. Execute all subsequent commands from within the `antenna-transmitter` directory.

2. Copy these files into the `antenna-transmitter` directory:
   - `transmitter-statefulset.yaml`: Kubernetes StatefulSet manifest
   - `transmitter-service.yaml`: Kubernetes Service manifest

**Expected Directory Structure:**

```
antenna-transmitter/
├── configs/
│   ├── js/
│   │   └── (transformation handlers)
│   ├── keys/
│   │   └── (certificates will be generated here)
│   ├── storage.yml
│   └── transmitter.yml
├── transmitter-service.yaml
└── transmitter-statefulset.yaml
```

### Generating Keys and Certificates

Generate SSL keys and certificates for secure communication using OpenSSL.

#### 1. Generate Server Certificate

```bash
$ openssl req -x509 -newkey rsa:4096 -keyout configs/keys/server.key \
    -out configs/keys/server.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=DNS:<hostname>" \
    -addext "subjectAltName = DNS:<hostname>"
```

Replace `<hostname>` with your actual hostname.

#### 2. Generate JWT Signing Key Pair

You also need a key pair to sign security event tokens:

```bash
$ openssl req -x509 -newkey rsa:4096 -keyout configs/keys/jwtsigner.key \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=DNS:<hostname>" \
    -out configs/keys/jwtsigner.pem -days 365 -nodes
```

### Creating Transformation Handlers

Transformation handlers process incoming raw events and convert them into SSF-standardized format. Example handlers are provided in the `configs/js` directory, including one that transforms device events from mobile device management systems (like IBM MaaS360) into SSF CAEP events for device compliance changes.

Add additional transformation handler files to this directory as needed.

### Configuring Authorization Scheme

The authorization scheme in `transmitter.yml` must be populated with valid values. These instructions use IBM Verify as the authorization server.

1. **Create a new API client in IBM Verify** following the [IBM Verify documentation](https://www.ibm.com/docs/en/security-verify?topic=access-creating-api-clients). No entitlements are required.
   - Note: The UI currently requires selecting an entitlement. Choose any arbitrary entitlement, save the client, then edit and remove the entitlement.

2. **Populate `transmitter.yml` with these values:**
   - `authorization_schemes[].client_id`: Client ID from step 1
   - `authorization_schemes[].client_secret`: Client secret from step 1
   - `authorization_schemes[].discovery_uri`: Replace the hostname with your IBM Verify tenant hostname

> 📘 Note
>
> Receivers connecting to this transmitter must generate OAuth tokens from the same IBM Verify tenant.
>
> Receivers require either a long-lived access token or OAuth client credentials (generated as an API client).

### Creating ConfigMaps and Secrets

Create ConfigMaps and Secrets using files from the `configs` directory. Names are critical as they're referenced in the Kubernetes deployment descriptor.

1. **Create ConfigMap for YAML configuration files**

    ```bash
    $ kubectl create configmap transmitter-config \
            --from-file=./configs/transmitter.yml \
            --from-file=./configs/storage.yml
    ```

2. **Create ConfigMap for transformation handlers**

    ```bash
    $ kubectl create configmap transmitter-transform-handlers \
            --from-file=configs/js
    ```

3. **Create Secret for TLS certificates**

    ```bash
    $ kubectl create secret generic transmitter-keys \
            --from-file=configs/keys
    ```

## Deploying to Kubernetes

1. **Create the Kubernetes StatefulSet**

    ```bash
    $ kubectl apply -f transmitter-statefulset.yaml
    ```

2. **Create the Kubernetes Service**

    ```bash
    $ kubectl apply -f transmitter-service.yaml
    ```

## Verifying the Deployment

1. **Verify the pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-transmitter
    ```

    Expected output:
    ```
    NAME                     READY   STATUS    RESTARTS   AGE
    antenna-transmitter-0    1/1     Running   0          2m
    ```

2. **Check pod logs**

    ```bash
    $ kubectl logs -l app=antenna-transmitter --tail=50
    ```

3. **Port-forward the service for local access**

    ```bash
    $ kubectl port-forward service/antenna-transmitter 9044:9044
    ```

4. **Test connectivity** by opening a browser and navigating to `https://localhost:9044/.well-known/ssf-configuration`.

5. **Test database connectivity from transmitter pod**

    ```bash
    $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
    ```

6. **Test Kafka connectivity from transmitter pod**

    ```bash
    $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
    ```

## Troubleshooting

### Transmitter Pod Not Starting

**Symptoms**: Transmitter pod remains in `Pending`, `CrashLoopBackOff`, or `Error` state.

**Solutions**:
1. Check pod logs for errors:
   ```bash
   $ kubectl logs -l app=antenna-transmitter
   ```

2. Verify all required ConfigMaps and Secrets exist:
   ```bash
   $ kubectl get configmap transmitter-config transmitter-transform-handlers
   $ kubectl get secret transmitter-keys antenna-postgres-secret antenna-kafka-secret
   ```

3. Check if datastore pods are running:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   $ kubectl get pods -l app=antenna-kafka
   ```

4. Verify PersistentVolumeClaim is bound:
   ```bash
   $ kubectl get pvc transmitter-db-antenna-transmitter-0
   ```

### Cannot Connect to PostgreSQL

**Symptoms**: Transmitter logs show database connection errors.

**Solutions**:
1. Verify PostgreSQL service is accessible:
   ```bash
   $ kubectl get svc antenna-postgres
   ```

2. Check PostgreSQL pod is running and ready:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   ```

3. Test PostgreSQL connectivity from transmitter pod:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
   ```

4. Verify PostgreSQL credentials in secrets:
   ```bash
   $ kubectl get secret antenna-postgres-secret -o yaml
   ```

### Cannot Connect to Kafka

**Symptoms**: Transmitter logs show Kafka connection or authentication errors.

**Solutions**:
1. Verify Kafka service is accessible:
   ```bash
   $ kubectl get svc antenna-kafka
   ```

2. Test Kafka connectivity from transmitter pod:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
   ```

3. Check Kafka credentials:
   ```bash
   $ kubectl get secret antenna-kafka-secret -o yaml
   ```

4. Verify Kafka topics exist:
   ```bash
   $ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-topics \
       --bootstrap-server antenna-kafka:9092 \
       --command-config /etc/kafka/clients/client.properties --list
   ```

### Transformation Handler Errors

**Symptoms**: Events are ingested but transformation fails.

**Solutions**:
1. Check transmitter logs for JavaScript errors:
   ```bash
   $ kubectl logs -l app=antenna-transmitter | grep -i error
   ```

2. Verify transformation handler files are mounted:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- ls -la /var/antenna/config/js/
   ```

3. Test transformation handler syntax locally before deploying.

4. Check for memory or CPU resource constraints that might affect complex handlers.

### Authorization/Authentication Issues

**Symptoms**: OAuth token validation errors or authorization failures.

**Solutions**:
1. Verify IBM Verify tenant configuration in transmitter.yml:
   ```bash
   $ kubectl get configmap transmitter-config -o yaml
   ```

2. Test OAuth token generation manually:
   ```bash
   $ curl -X POST https://tenant.verify.ibm.com/v1.0/endpoint/default/token \
       -H "Content-Type: application/x-www-form-urlencoded" \
       -d "grant_type=client_credentials&client_id=<client_id>&client_secret=<client_secret>"
   ```

3. Verify API client has correct permissions in IBM Verify.

### Certificate Errors

**Symptoms**: SSL/TLS handshake failures or certificate validation errors.

**Solutions**:
1. Verify certificate validity:
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout
   $ openssl x509 -in configs/keys/jwtsigner.pem -text -noout
   ```

2. Check Subject Alternative Names (SAN):
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout | grep -A1 "Subject Alternative Name"
   ```

3. Regenerate certificates if expired or incorrect.

### General Troubleshooting Commands

```bash
# View all resources
$ kubectl get all

# Check pod logs
$ kubectl logs <pod-name> --tail=100 -f

# Check events
$ kubectl get events --sort-by='.lastTimestamp'

# Describe resource
$ kubectl describe <resource-type> <resource-name>

# Execute command in pod
$ kubectl exec -it <pod-name> -- bash

# Port forward for local access
$ kubectl port-forward service/<service-name> <local-port>:<service-port>

# Check resource usage
$ kubectl top pods
$ kubectl top nodes
