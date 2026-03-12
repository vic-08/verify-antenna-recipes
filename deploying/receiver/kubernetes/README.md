# IBM Verify Antenna Receiver Kubernetes Deployment Guide

This guide provides step-by-step instructions for deploying an IBM Verify Antenna Receiver on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [Required Tools](#required-tools)
  - [Kubernetes Cluster](#kubernetes-cluster)
  - [Prerequisites Deployment](#prerequisites-deployment)
- [Receiver Configuration](#receiver-configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
- [Generating Receiver Keys and Certificates](#generating-receiver-keys-and-certificates)
- [Creating Action Handlers](#creating-action-handlers)
- [Configuring TLS for Transmitter Connections](#configuring-tls-for-transmitter-connections)
- [Creating Receiver ConfigMaps and Secrets](#creating-receiver-configmaps-and-secrets)
- [Deploying Receiver to Kubernetes](#deploying-receiver-to-kubernetes)
- [Verifying Receiver Deployment](#verifying-receiver-deployment)
- [Troubleshooting](#troubleshooting)
  - [Receiver Pod Not Starting](#receiver-pod-not-starting)
  - [Action Handler Errors](#action-handler-errors)
  - [Certificate Errors](#certificate-errors)
  - [General Troubleshooting Commands](#general-troubleshooting-commands)

## Overview

The IBM Verify Antenna Receiver receives and processes security events from transmitters using the OpenID Shared Signals Framework (SSF). It supports various event types including session revocation, credential changes, device compliance changes, and custom event types.

## Prerequisites

### Required Tools

- **kubectl**: Kubernetes command‑line tool (version 1.20 or later)
- **openssl**: For generating SSL/TLS certificates

### Kubernetes Cluster

- **Kubernetes version**: 1.20 or later
- **Resources**: Minimum of 4 CPU cores and 8 GB RAM
- **Access**: Cluster administrator permissions required for creating resources

### Prerequisites Deployment

- **Datastore**: PostgreSQL and Kafka must be deployed first. Follow the [Datastore Deployment Guide](../datastore/kubernetes/README.md).
- **Transmitter**: The transmitter should be deployed and configured. Follow the [Transmitter Deployment Guide](../transmitter/kubernetes/README.md).

## Receiver Configuration

### Setting Up the Local Directory

> 📘 **Note**
>
> Skip this section if you already cloned the GitHub repository.

Create a directory structure that matches the receiver layout:

1. Create a directory named `antenna-receiver` and copy the `deploying/receiver/container-runtime/configs` folder into it. All subsequent commands must be executed from the `antenna-receiver` directory.

2. Copy the following files from `deploying/receiver/kubernetes` into the `antenna-receiver` directory:
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

### Generating Receiver Keys and Certificates

Generate SSL/TLS keys and certificates for secure communication using OpenSSL.

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

Replace `<hostname>` with your actual hostname, or use `antenna-receiver` for internal cluster communication.

### Creating Action Handlers

Action handlers process different event types and execute specific actions based on event data. A sample action handler that logs event details to standard output is provided in `log_event.js` within the `configs/js` directory.

Add custom action handler files to this directory as required for your use case.

### Configuring TLS for Transmitter Connections

If the Receiver must connect to a Transmitter that uses a non-standard or self‑signed CA certificate, complete the following steps:

1. **Obtain the transmitter's public certificate** by accessing the transmitter's `/.well-known/ssf-configuration` endpoint and exporting the certificate.

2. **Create a `ca-bundle.pem` file** in the `configs/keys` directory.

3. **Add the public certificate** to the `ca-bundle.pem` file.

4. **Uncomment lines 27–29 in `receiver-deployment.yaml`** to configure the receiver to use the custom CA bundle (remove the `#` prefix from each line):

    ```yaml
        env:
          - name: SSL_CERT_FILE
            value: /var/antenna/config/keys/ca-bundle.pem
    ```

### Creating Receiver ConfigMaps and Secrets

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

3. **Create Secret for SSL/TLS certificates**

    ```bash
    $ kubectl create secret generic receiver-keys \
            --from-file=configs/keys
    ```

### Deploying Receiver to Kubernetes

> 📘 **Scaling Receiver Pods**
>
> To deploy multiple receiver pods for increased throughput:
> 1. Update the `replicas` field (line 8) in `receiver-deployment.yaml` to the desired pod count
> 2. Adjust the `worker_threads` configuration (line 20) in `receiver.yml` as needed
> 3. Ensure the Kafka topic partition count for `antenna.ssf_2_action.event.queue` matches: `replicas × worker_threads` (refer to the "Creating Kafka Topics" section)

1. **Create the Kubernetes Deployment**

    ```bash
    $ kubectl apply -f receiver-deployment.yaml
    ```

2. **Create the Kubernetes Service**

    ```bash
    $ kubectl apply -f receiver-service.yaml
    ```

### Verifying Receiver Deployment

1. **Verify the pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-receiver
    ```

    Expected output:
    ```
    NAME                                READY   STATUS    RESTARTS   AGE
    antenna-receiver-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
    ```

2. **Check pod logs for errors**

    ```bash
    $ kubectl logs -l app=antenna-receiver --tail=50
    ```

3. **Port-forward the service for local access**

    ```bash
    $ kubectl port-forward service/antenna-receiver 9043:9043
    ```

4. **Test connectivity** by opening a web browser and navigating to `https://localhost:9043/mgmt/v1.0/receivers/config`.

5. **Test PostgreSQL connectivity from receiver pod**

    ```bash
    $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
    ```

6. **Test Kafka connectivity from receiver pod**

    ```bash
    $ kubectl exec <receiver-pod-name> -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
    ```

### Troubleshooting

#### Receiver Pod Not Starting

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

3. Verify the datastore pods are running:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   $ kubectl get pods -l app=antenna-kafka
   ```

#### Action Handler Errors

**Symptoms**: Events are received successfully but action processing fails.

**Solutions**:

1. Check receiver logs for JavaScript errors:
   ```bash
   $ kubectl logs -l app=antenna-receiver | grep -i error
   ```

2. Verify action handler files are properly mounted:
   ```bash
   $ kubectl exec <receiver-pod-name> -- ls -la /var/antenna/config/js/
   ```

3. Validate action handler syntax locally before deploying to the cluster.

#### Certificate Errors

**Symptoms**: SSL/TLS handshake failures or certificate validation errors.

**Solutions**:

1. Verify certificate validity and expiration:
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout
   ```

2. Verify Subject Alternative Names (SAN) are correct:
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

5. Regenerate certificates if they are expired or contain incorrect information.

#### General Troubleshooting Commands

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

```
