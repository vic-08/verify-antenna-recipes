# IBM Verify Antenna Transmitter Kubernetes Deployment Guide

This guide provides step-by-step instructions for deploying an IBM Verify Antenna Transmitter on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [Required Tools](#required-tools)
  - [Kubernetes Cluster](#kubernetes-cluster)
  - [IBM Verify Tenant](#ibm-verify-tenant)
  - [Prerequisites Deployment](#prerequisites-deployment)
- [Transmitter Configuration](#transmitter-configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
- [Generating Transmitter Keys and Certificates](#generating-transmitter-keys-and-certificates)
  - [1. Generate Server Certificate](#1-generate-server-certificate)
  - [2. Generate JWT Signing Key Pair](#2-generate-jwt-signing-key-pair)
- [Creating Transformation Handlers](#creating-transformation-handlers)
- [Configuring Authorization Scheme](#configuring-authorization-scheme)
- [Creating Transmitter ConfigMaps and Secrets](#creating-transmitter-configmaps-and-secrets)
- [Deploying Transmitter to Kubernetes](#deploying-transmitter-to-kubernetes)
- [Verifying Transmitter Deployment](#verifying-transmitter-deployment)
- [Troubleshooting](#troubleshooting)
  - [Transmitter Pod Not Starting](#transmitter-pod-not-starting)
  - [Cannot Connect to PostgreSQL](#cannot-connect-to-postgresql)
  - [Cannot Connect to Kafka](#cannot-connect-to-kafka)
  - [Transformation Handler Errors](#transformation-handler-errors)
  - [Authorization and Authentication Issues](#authorization-and-authentication-issues)
  - [Certificate Errors](#certificate-errors)
  - [General Troubleshooting Commands](#general-troubleshooting-commands)

## Overview

The IBM Verify Antenna Transmitter ingests raw security events, transforms them into SSF-compliant format, and transmits them to registered SSF receivers.

> 📘 **Performance Note**
>
> Transformation handler complexity directly impacts resource requirements and processing throughput. Use simple object-to-object mapping whenever possible. Avoid augmenting events with data from external API calls, as this significantly reduces performance.

## Prerequisites

### Required Tools

- **kubectl**: Kubernetes command‑line tool (version 1.20 or later)
- **openssl**: For generating SSL/TLS certificates

### Kubernetes Cluster

- **Kubernetes version**: 1.20 or later
- **Storage**: Dynamic volume provisioning enabled or pre-created PersistentVolumes
- **Resources**: Minimum of 4 CPU cores and 8 GB RAM
- **Access**: Cluster administrator permissions required for creating resources

### IBM Verify Tenant

- Sign up for a free trial at [ibm.biz/verify-trial](https://ibm.biz/verify-trial)
- Note your tenant hostname (for example, `tenant.verify.ibm.com`). You will reference this hostname in configuration files

### Prerequisites Deployment

- **Datastore**: PostgreSQL and Kafka must be deployed first. Follow the [Datastore Deployment Guide](../datastore/kubernetes/README.md).

## Transmitter Configuration

### Setting Up the Local Directory

> 📘 **Note**
>
> Skip this section if you already cloned the GitHub repository.

Create a directory structure that matches the transmitter layout:

1. Create a directory named `antenna-transmitter` and copy the `deploying/transmitter/container-runtime/configs` folder into it. All subsequent commands must be executed from the `antenna-transmitter` directory.

2. Copy the following files from `deploying/transmitter/kubernetes` into the `antenna-transmitter` directory:
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

## Generating Transmitter Keys and Certificates

Generate SSL/TLS keys and certificates for secure communication using OpenSSL.

### 1. Generate Server Certificate

```bash
$ openssl req -x509 -newkey rsa:4096 -keyout configs/keys/server.key \
    -out configs/keys/server.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=DNS:<hostname>" \
    -addext "subjectAltName = DNS:<hostname>"
```

Replace `<hostname>` with your actual hostname, or use `antenna-transmitter` for internal cluster communication.

### 2. Generate JWT Signing Key Pair

Generate a key pair for signing security event tokens:

```bash
$ openssl req -x509 -newkey rsa:4096 -keyout configs/keys/jwtsigner.key \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=DNS:<hostname>" \
    -out configs/keys/jwtsigner.pem -days 365 -nodes
```

## Creating Transformation Handlers

Transformation handlers process incoming raw events and convert them into SSF-standardized format. Sample handlers are provided in the `configs/js` directory, including an example that transforms device events from mobile device management systems (such as IBM MaaS360) into SSF CAEP (Continuous Access Evaluation Profile) events for device compliance changes.

Add custom transformation handler files to this directory as required for your use case.

## Configuring Authorization Scheme

The authorization scheme in `transmitter.yml` must be configured with valid credentials. These instructions use IBM Verify as the authorization server.

1. **Create a new API client in IBM Verify** by following the [IBM Verify documentation](https://www.ibm.com/docs/en/security-verify?topic=access-creating-api-clients). No entitlements are required.
   - **Note**: The UI currently requires selecting an entitlement during creation. Select any entitlement, save the client, then edit the client and remove the entitlement.

2. **Update `transmitter.yml` with the following values:**
   - `authorization_schemes[].client_id`: Client ID from step 1
   - `authorization_schemes[].client_secret`: Client secret from step 1
   - `authorization_schemes[].discovery_uri`: Update the hostname with your IBM Verify tenant hostname

> 📘 **Authentication Requirements**
>
> Receivers connecting to this transmitter must obtain OAuth tokens from the same IBM Verify tenant.
>
> Receivers require either a long-lived access token or OAuth client credentials (created as an API client in IBM Verify).

## Creating Transmitter ConfigMaps and Secrets

Create ConfigMaps and Secrets using files from the `configs` directory. Resource names must match exactly as they are referenced in the Kubernetes deployment manifests.

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

3. **Create Secret for SSL/TLS certificates**

    ```bash
    $ kubectl create secret generic transmitter-keys \
            --from-file=configs/keys
    ```

## Deploying Transmitter to Kubernetes

> 📘 **Scaling Transmitter Pods**
>
> To deploy multiple transmitter pods for increased throughput:
> 1. Update the `replicas` field (line 8) in `transmitter-statefulset.yaml` to the desired pod count
> 2. Adjust the `worker_threads` configuration (line 35) in `transmitter.yml` as needed
> 3. Ensure the Kafka topic partition count for `antenna.raw_2_ssf.event.queue` matches: `replicas × worker_threads` (refer to the "Creating Kafka Topics" section)

1. **Create the Kubernetes StatefulSet**

    ```bash
    $ kubectl apply -f transmitter-statefulset.yaml
    ```

2. **Create the Kubernetes Service**

    ```bash
    $ kubectl apply -f transmitter-service.yaml
    ```

## Verifying Transmitter Deployment

1. **Verify the pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-transmitter
    ```

    Expected output:
    ```
    NAME                     READY   STATUS    RESTARTS   AGE
    antenna-transmitter-0    1/1     Running   0          2m
    ```

2. **Check pod logs for errors**

    ```bash
    $ kubectl logs -l app=antenna-transmitter --tail=50
    ```

3. **Port-forward the service for local access**

    ```bash
    $ kubectl port-forward service/antenna-transmitter 9044:9044
    ```

4. **Test connectivity** by opening a web browser and navigating to `https://localhost:9044/.well-known/ssf-configuration`.

5. **Test PostgreSQL connectivity from transmitter pod**

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

3. Verify the datastore pods are running:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   $ kubectl get pods -l app=antenna-kafka
   ```

4. Verify the PersistentVolumeClaim is bound:
   ```bash
   $ kubectl get pvc transmitter-db-antenna-transmitter-0
   ```

### Cannot Connect to PostgreSQL

**Symptoms**: Transmitter logs show database connection errors.

**Solutions**:

1. Verify the PostgreSQL service is accessible:
   ```bash
   $ kubectl get svc antenna-postgres
   ```

2. Verify the PostgreSQL pod is running and ready:
   ```bash
   $ kubectl get pods -l app=antenna-postgres
   ```

3. Test PostgreSQL connectivity from the transmitter pod:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-postgres/5432" && echo "PostgreSQL is reachable" || echo "Cannot connect to PostgreSQL"'
   ```

4. Verify PostgreSQL credentials are configured correctly:
   ```bash
   $ kubectl get secret antenna-postgres-secret -o yaml
   ```

### Cannot Connect to Kafka

**Symptoms**: Transmitter logs show Kafka connection or authentication errors.

**Solutions**:

1. Verify the Kafka service is accessible:
   ```bash
   $ kubectl get svc antenna-kafka
   ```

2. Test Kafka connectivity from the transmitter pod:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- bash -c 'timeout 2 bash -c "</dev/tcp/antenna-kafka/9092" && echo "Kafka is reachable" || echo "Cannot connect to Kafka"'
   ```

3. Verify Kafka credentials are configured correctly:
   ```bash
   $ kubectl get secret antenna-kafka-secret -o yaml
   ```

4. Verify the required Kafka topics exist:
   ```bash
   $ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-topics \
       --bootstrap-server antenna-kafka:9092 \
       --command-config /etc/kafka/clients/client.properties --list
   ```

### Transformation Handler Errors

**Symptoms**: Events are ingested successfully but transformation processing fails.

**Solutions**:

1. Check transmitter logs for JavaScript errors:
   ```bash
   $ kubectl logs -l app=antenna-transmitter | grep -i error
   ```

2. Verify transformation handler files are properly mounted:
   ```bash
   $ kubectl exec antenna-transmitter-0 -- ls -la /var/antenna/config/js/
   ```

3. Validate transformation handler syntax locally before deploying to the cluster.

4. Check for memory or CPU resource constraints that may impact complex handler execution.

### Authorization and Authentication Issues

**Symptoms**: OAuth token validation errors or authorization failures in logs.

**Solutions**:

1. Verify the IBM Verify tenant configuration in transmitter.yml:
   ```bash
   $ kubectl get configmap transmitter-config -o yaml
   ```

2. Test OAuth token generation manually:
   ```bash
   $ curl -X POST https://tenant.verify.ibm.com/v1.0/endpoint/default/token \
       -H "Content-Type: application/x-www-form-urlencoded" \
       -d "grant_type=client_credentials&client_id=<client_id>&client_secret=<client_secret>"
   ```

3. Verify the API client has the correct permissions configured in IBM Verify.

### Certificate Errors

**Symptoms**: SSL/TLS handshake failures or certificate validation errors.

**Solutions**:

1. Verify certificate validity and expiration:
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout
   $ openssl x509 -in configs/keys/jwtsigner.pem -text -noout
   ```

2. Verify Subject Alternative Names (SAN) are correct:
   ```bash
   $ openssl x509 -in configs/keys/server.pem -text -noout | grep -A1 "Subject Alternative Name"
   ```

3. Regenerate certificates if they are expired or contain incorrect information.

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

```
