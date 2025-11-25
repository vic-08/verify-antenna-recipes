# IBM Verify Antenna Receiver Kubernetes Deployment Guide

This guide walks you through deploying an IBM Verify Antenna Receiver on Kubernetes to process security events that comply with the OpenID Shared Signals Framework (SSF).

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
  - [Generating Keys and Certificates](#generating-keys-and-certificates)
  - [Creating Action Handlers](#creating-action-handlers)
  - [Configuring TLS for Transmitter Connections](#configuring-tls-for-transmitter-connections)
  - [Creating ConfigMaps and Secrets](#creating-configmaps-and-secrets)
- [Deploying to Kubernetes](#deploying-to-kubernetes)
- [Verifying the Deployment](#verifying-the-deployment)
- [Troubleshooting](#troubleshooting)

## Overview

The IBM Verify Antenna Receiver receives and processes security events from transmitters using the OpenID Shared Signals Framework (SSF). It handles various event types, including session revocation, credential changes, device compliance changes, and custom events.

## Prerequisites

### Required Tools

- **kubectl**: Kubernetes command-line tool (v1.20+)
- **openssl**: For generating SSL/TLS certificates

### Kubernetes Cluster

- **Kubernetes version**: 1.20 or higher
- **Resources**: Minimum 2 CPU cores and 4GB RAM available
- **Access**: Cluster admin permissions for creating resources

### Prerequisites Deployment

- **Datastore**: PostgreSQL and Kafka must be deployed first. Follow the [Datastore Deployment Guide](../datastore/README.md).
- **Transmitter**: The transmitter should be deployed and configured. Follow the [Transmitter Deployment Guide](../transmitter/README.md).

## Configuration

### Setting Up the Local Directory

> 📘 Note
>
> Perform these steps only if you haven't cloned this GitHub repository to your local system.

Build a directory structure matching the [configs](./configs) layout:

1. Create a directory named `antenna-receiver` on your system and copy the contents of the [configs](./configs) directory into it. Execute all subsequent commands from within the `antenna-receiver` directory.

2. Copy these files into the `antenna-receiver` directory:
   - `receiver-deployment.yaml`: Kubernetes Deployment manifest
   - `receiver-service.yaml`: Kubernetes Service manifest

**Expected Directory Structure:**

```
antenna-receiver/
├── configs/
│   ├── custom_events.yml
│   ├── js/
│   │   └── (action handlers)
│   ├── keys/
│   │   └── (certificates will be generated here)
│   ├── receiver.yml
│   └── storage.yml
├── receiver-deployment.yaml
└── receiver-service.yaml
```

### Generating Keys and Certificates

Generate SSL keys and certificates for secure communication using OpenSSL.

```bash
$ openssl req -x509 \
        -newkey rsa:4096 \
        -keyout configs/keys/server.key \
        -out configs/keys/server.pem \
        -days 365 \
        -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=DNS:<hostname>" \
        -addext "subjectAltName = DNS:<hostname>"
```

Replace `<hostname>` with your actual hostname.

### Creating Action Handlers

Action handlers process different event types and perform specific actions based on event data. A sample action handler that logs event details to standard output is provided at `log_event.js` in the `configs/js` directory.

Add additional action handler files to this directory as needed.

### Configuring TLS for Transmitter Connections

If connecting this receiver to a transmitter using a non-standard CA certificate or self-signed certificate, follow these steps:

1. **Obtain the transmitter's public certificate** by accessing the `/.well-known/ssf-configuration` endpoint and exporting the certificate.

2. **Create a `ca-bundle.pem` file** in the `configs/keys` directory.

3. **Copy the public certificate** into the `ca-bundle.pem` file.

4. **Uncomment lines 27–29 in `receiver-deployment.yaml`** to override the CA bundle used by the receiver (remove the `#` prefix):

    ```yaml
        env:
          - name: SSL_CERT_FILE
            value: /var/antenna/config/keys/ca-bundle.pem
    ```

### Creating ConfigMaps and Secrets

1. **Create ConfigMap for YAML configuration files**

    ```bash
    $ kubectl create configmap receiver-config \
            --from-file=./configs/receiver.yml \
            --from-file=./configs/storage.yml \
            --from-file=./configs/custom_events.yml
    ```

2. **Create ConfigMap for action handlers**

    ```bash
    $ kubectl create configmap receiver-action-handlers \
            --from-file=configs/js
    ```

3. **Create Secret for TLS certificates**

    ```bash
    $ kubectl create secret generic receiver-keys \
            --from-file=configs/keys
    ```

## Deploying to Kubernetes

1. **Create the Kubernetes Deployment**

    ```bash
    $ kubectl apply -f receiver-deployment.yaml
    ```

2. **Create the Kubernetes Service**

    ```bash
    $ kubectl apply -f receiver-service.yaml
    ```

## Verifying the Deployment

1. **Verify the pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-receiver
    ```

    Expected output:
    ```
    NAME                                READY   STATUS    RESTARTS   AGE
    antenna-receiver-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
    ```

2. **Check pod logs**

    ```bash
    $ kubectl logs -l app=antenna-receiver --tail=50
    ```

3. **Port-forward the service for local access**

    ```bash
    $ kubectl port-forward service/antenna-receiver 9043:9043
    ```

4. **Test connectivity** by opening a browser and navigating to `https://localhost:9043/mgmt/v1.0/receivers/config`.

5. **Test database connectivity from receiver pod**

    ```bash
    $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
    ```

6. **Test Kafka connectivity from receiver pod**

    ```bash
    $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
    ```

## Troubleshooting

### Receiver Pod Not Starting

**Symptoms**: Receiver pod remains in `Pending`, `CrashLoopBackOff`, or `Error` state.

**Solutions**:
1. Check pod logs for errors:
   ```bash
   $ kubectl logs -l app=antenna-receiver
   ```

2. Verify all required ConfigMaps and Secrets exist:
   ```bash
   $ kubectl get configmap receiver-config receiver-action-handlers
   $ kubectl get secret receiver-keys antenna-postgres-secret antenna-kafka-secret
   ```

3. Check if datastore pods are running:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   $ kubectl get pods -l app=antenna-kafka
   ```

### Cannot Connect to PostgreSQL

**Symptoms**: Receiver logs show database connection errors.

**Solutions**:
1. Verify PostgreSQL service is accessible:
   ```bash
   $ kubectl get svc antenna-postgres
   ```

2. Check PostgreSQL pod is running and ready:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   ```

3. Test PostgreSQL connectivity from receiver pod:
   ```bash
   $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
   ```

4. Verify PostgreSQL credentials in secrets:
   ```bash
   $ kubectl get secret antenna-postgres-secret -o yaml
   ```

### Cannot Connect to Kafka

**Symptoms**: Receiver logs show Kafka connection or authentication errors.

**Solutions**:
1. Verify Kafka service is accessible:
   ```bash
   $ kubectl get svc antenna-kafka
   ```

2. Test Kafka connectivity from receiver pod:
   ```bash
   $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
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

### Action Handler Errors

**Symptoms**: Events are received but not processed correctly.

**Solutions**:
1. Check receiver logs for JavaScript errors:
   ```bash
   $ kubectl logs -l app=antenna-receiver | grep -i error
   ```

2. Verify action handler files are mounted:
   ```bash
   $ kubectl exec <receiver-pod-name> -- ls -la /var/antenna/config/js/
   ```

3. Test action handler syntax locally before deploying.

### Certificate Errors

**Symptoms**: SSL/TLS handshake failures or certificate validation errors.

**Solutions**:
1. Verify certificate validity:
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout
   ```

2. Check Subject Alternative Names (SAN):
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout | grep -A1 "Subject Alternative Name"
   ```

3. If using custom CA bundle, ensure it's properly mounted:
   ```bash
   $ kubectl exec <receiver-pod-name> -- cat /var/antenna/config/keys/ca-bundle.pem
   ```

4. Check SSL_CERT_FILE environment variable if set:
   ```bash
   $ kubectl exec <receiver-pod-name> -- env | grep SSL_CERT_FILE
   ```

5. Regenerate certificates if expired or incorrect.

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
