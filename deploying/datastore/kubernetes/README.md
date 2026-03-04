# IBM Verify Antenna Datastore Kubernetes Deployment Guide

This guide provides step-by-step instructions for deploying the datastore components (PostgreSQL and Kafka) required for IBM Verify Antenna on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [Required Tools](#required-tools)
  - [Kubernetes Cluster](#kubernetes-cluster)
- [Datastore Configuration](#datastore-configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
- [Generating Datastore Keys and Certificates](#generating-datastore-keys-and-certificates)
  - [1. Generate CA Key and Certificate](#1-generate-ca-key-and-certificate)
  - [2. Generate PostgreSQL SSL Certificate](#2-generate-postgresql-ssl-certificate)
  - [3. Generate Kafka SSL Certificate](#3-generate-kafka-ssl-certificate)
  - [4. Create Kafka PEM Keystore and Truststore](#4-create-kafka-pem-keystore-and-truststore)
- [Creating Datastore ConfigMaps and Secrets](#creating-datastore-configmaps-and-secrets)
  - [PostgreSQL ConfigMaps and Secrets](#postgresql-configmaps-and-secrets)
  - [Kafka ConfigMaps and Secrets](#kafka-configmaps-and-secrets)
- [Deploying Datastore to Kubernetes](#deploying-datastore-to-kubernetes)
- [Verifying Datastore Deployment](#verifying-datastore-deployment)
- [Creating Kafka Topics](#creating-kafka-topics)
- [Troubleshooting](#troubleshooting)
  - [PostgreSQL Pod Not Starting](#postgresql-pod-not-starting)
  - [Kafka Pod Not Starting](#kafka-pod-not-starting)
  - [Cannot Create Kafka Topics](#cannot-create-kafka-topics)
  - [Certificate Errors](#certificate-errors)
  - [General Troubleshooting Commands](#general-troubleshooting-commands)

## Overview

The datastore includes PostgreSQL database and Kafka message broker servers required for IBM Verify Antenna. These components must be deployed before the transmitter and receiver.

## Prerequisites

### Required Tools

- **kubectl**: Kubernetes command‑line tool (version 1.20 or later)
- **openssl**: For generating SSL/TLS certificates
- **keytool**: Java keytool for creating Kafka keystores (included with JDK)

### Kubernetes Cluster

- **Kubernetes version**: 1.20 or later
- **Storage**: Dynamic volume provisioning enabled or pre-created PersistentVolumes
- **Resources**: Minimum of 4 CPU cores and 8 GB RAM
- **Access**: Cluster administrator permissions required for creating resources

## Datastore Configuration

### Setting Up the Local Directory

> 📘 **Note**
>
> Skip this section if you already cloned the GitHub repository.

Create a directory structure that matches the datastore layout:

1. Create a directory named `antenna-datastore` and copy the `deploying/datastore/container-runtime/configs` folder into it. All subsequent commands must be executed from the `antenna-datastore` directory.

2. Copy the following files from `deploying/datastore/kubernetes` into the `antenna-datastore` directory:
   - `datastore-statefulset.yaml`: Kubernetes StatefulSet manifest
   - `datastore-service.yaml`: Kubernetes Service manifest

**Expected Directory Structure:**

```
antenna-datastore/
├── configs/
│   ├── init_pg_schema.sql
│   ├── kafka-client.properties.template
│   ├── kafka_entrypoint.sh
│   ├── keys/
│   │   └── (certificates will be generated here)
│   ├── pg_hba.conf
│   ├── san-kafka.cnf
│   ├── san-postgres.cnf
│   └── secrets/
│       └── (secrets will be generated here)
├── datastore-service.yaml
└── datastore-statefulset.yaml
```

## Generating Datastore Keys and Certificates

Generate SSL/TLS keys and certificates for secure communication using OpenSSL.

### 1. Generate CA Key and Certificate

```bash
$ openssl genrsa 4096 > configs/keys/ca.key
```

```bash
$ openssl req -new -x509 -nodes -days 3650 \
    -key configs/keys/ca.key -out configs/keys/ca.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=CA"
```

### 2. Generate PostgreSQL SSL Certificate

```bash
$ openssl req -newkey rsa:4096 -sha256 \
    -keyout configs/keys/postgres.key \
    -out configs/keys/postgres.csr -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=antenna-postgres" \
    -addext "subjectAltName = DNS:antenna-postgres"
```

```bash
$ openssl x509 -req -days 365 -in configs/keys/postgres.csr \
    -out configs/keys/postgres.pem -CA configs/keys/ca.pem \
    -CAkey configs/keys/ca.key \
    -extensions v3_req -extfile configs/san-postgres.cnf
```

### 3. Generate Kafka SSL Certificate

```bash
$ openssl req -newkey rsa:4096 -sha256 \
    -keyout configs/keys/kafka.key \
    -out configs/keys/kafka.csr -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=antenna-kafka" \
    -addext "subjectAltName = DNS:antenna-kafka,DNS:antenna-kafka-0.antenna-kafka"
```

```bash
$ openssl x509 -req -days 365 -in configs/keys/kafka.csr \
    -out configs/keys/kafka.pem -CA configs/keys/ca.pem \
    -CAkey configs/keys/ca.key \
    -extensions v3_req -extfile configs/san-kafka.cnf
```

### 4. Create Kafka PEM Keystore and Truststore

```bash
$ export ANTENNA_KAFKA_P12_PASSWORD=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
```

```bash
$ openssl pkcs12 -export \
    -inkey configs/keys/kafka.key \
    -in configs/keys/kafka.pem \
    -out configs/keys/kafka.p12 \
    -name kafka \
    -password pass:${ANTENNA_KAFKA_P12_PASSWORD}
```

```bash
$ export ANTENNA_KAFKA_JKS_PASSWORD=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
```

```bash
$ keytool -importkeystore -noprompt -v \
    -srcstorepass ${ANTENNA_KAFKA_P12_PASSWORD} \
    -deststorepass ${ANTENNA_KAFKA_JKS_PASSWORD} \
    -srckeystore configs/keys/kafka.p12 \
    -destkeystore configs/keys/kafka.jks \
    -srcstoretype PKCS12
```

```bash
$ keytool -import -noprompt -v \
    -trustcacerts -alias ca \
    -deststorepass ${ANTENNA_KAFKA_JKS_PASSWORD} \
    -keystore configs/keys/kafka.jks \
    -file configs/keys/ca.pem
```

## Creating Datastore ConfigMaps and Secrets

### PostgreSQL ConfigMaps and Secrets

1. **Create ConfigMap for PostgreSQL configuration files**

    ```bash
    $ kubectl create configmap antenna-postgres-config \
        --from-file=configs/pg_hba.conf \
        --from-file=configs/init_pg_schema.sql
    ```

2. **Create ConfigMap for PostgreSQL environment variables**

    ```bash
    $ kubectl create configmap antenna-postgres-env \
        --from-literal=POSTGRES_DB=antenna \
        --from-literal=POSTGRES_HOST=antenna-postgres \
        --from-literal=POSTGRES_PORT=5432 \
        --from-literal=POSTGRES_SSLMODE=require
    ```

3. **Create Secret for PostgreSQL credentials**

    ```bash
    $ kubectl create secret generic antenna-postgres-secret \
        --from-literal=POSTGRES_USER=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32) \
        --from-literal=POSTGRES_PASSWORD=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
    ```

4. **Create Secret for PostgreSQL SSL certificates**

    ```bash
    $ kubectl create secret generic antenna-postgres-cert \
        --from-file=ca.pem=configs/keys/ca.pem \
        --from-file=tls.pem=configs/keys/postgres.pem \
        --from-file=tls.key=configs/keys/postgres.key
    ```

### Kafka ConfigMaps and Secrets

1. **Create ConfigMap for Kafka configuration files**

    ```bash
    $ kubectl create configmap antenna-kafka-config \
        --from-file=configs/kafka_entrypoint.sh
    ```

2. **Create ConfigMap for Kafka environment variables**

    ```bash
    $ kubectl create configmap antenna-kafka-env \
        --from-literal=CLUSTER_ID=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 16) \
        --from-literal=KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
        --from-literal=KAFKA_CONTROLLER_QUORUM_VOTERS=0@antenna-kafka-0:9093 \
        --from-literal=KAFKA_INTER_BROKER_LISTENER_NAME=BROKER \
        --from-literal=KAFKA_LISTENERS=BROKER://:9092,CONTROLLER://:9093 \
        --from-literal=KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=BROKER:SASL_SSL,CONTROLLER:SASL_PLAINTEXT \
        --from-literal=KAFKA_LOG4J_LOGGERS=kafka=WARN,kafka.controller=WARN,kafka.log.LogCleaner=WARN,state.change.logger=WARN,kafka.producer.async.DefaultEventHandler=WARN \
        --from-literal=KAFKA_LOG4J_ROOT_LOGLEVEL=WARN \
        --from-literal=KAFKA_LOG4J_TOOLS_LOGLEVEL=ERROR \
        --from-literal=KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        --from-literal=KAFKA_OPTS=-Djava.security.debug=gssloginconfig,configfile,configparser,logincontext \
        --from-literal=KAFKA_PROCESS_ROLES=broker,controller \
        --from-literal=KAFKA_SASL_ENABLED_MECHANISMS=PLAIN \
        --from-literal=KAFKA_SASL_MECHANISM_CONTROLLER_PROTOCOL=PLAIN \
        --from-literal=KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN
    ```

3. **Create Secret for Kafka credentials**

    ```bash
    $ export KAFKA_CLIENT_USERS=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
    ```

    ```bash
    $ export KAFKA_CLIENT_PASSWORDS=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
    ```

    ```bash
    $ kubectl create secret generic antenna-kafka-secret \
        --from-literal=KAFKA_CLIENT_USERS=${KAFKA_CLIENT_USERS} \
        --from-literal=KAFKA_CLIENT_PASSWORDS=${KAFKA_CLIENT_PASSWORDS} \
        --from-literal=KAFKA_CONTROLLER_USER=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32) \
        --from-literal=KAFKA_CONTROLLER_PASSWORD=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
    ```

4. **Create Secret for Kafka SSL certificates**

    ```bash
    $ kubectl create secret generic antenna-kafka-cert \
        --from-file=ca.pem=configs/keys/ca.pem \
        --from-file=tls.pem=configs/keys/kafka.pem \
        --from-file=tls.key=configs/keys/kafka.key \
        --from-file=keystore.p12=configs/keys/kafka.p12 \
        --from-file=truststore.jks=configs/keys/kafka.jks \
        --from-literal=keystore_password=${ANTENNA_KAFKA_P12_PASSWORD} \
        --from-literal=truststore_password=${ANTENNA_KAFKA_JKS_PASSWORD}
    ```

5. **Create Secret for Kafka client configuration**

    ```bash
    $ cp configs/kafka-client.properties.template configs/secrets/kafka-client.properties
    ```

    ```bash
    $ echo "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${KAFKA_CLIENT_USERS}\" password=\"${KAFKA_CLIENT_PASSWORDS}\";" >> configs/secrets/kafka-client.properties
    ```

    ```bash
    $ echo ssl.truststore.password=${ANTENNA_KAFKA_JKS_PASSWORD} >> configs/secrets/kafka-client.properties
    ```

    ```bash
    $ kubectl create secret generic antenna-kafka-client-config \
        --from-file=client.properties=configs/secrets/kafka-client.properties
    ```

## Deploying Datastore to Kubernetes

1. **Create the datastore StatefulSet**

    ```bash
    $ kubectl apply -f datastore-statefulset.yaml
    ```

2. **Create the datastore Service**

    ```bash
    $ kubectl apply -f datastore-service.yaml
    ```

## Verifying Datastore Deployment

1. **Verify PostgreSQL pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-postgres
    ```

    Expected output:
    ```
    NAME                 READY   STATUS    RESTARTS   AGE
    antenna-postgres-0   1/1     Running   0          2m
    ```

2. **Verify Kafka pod is running**

    ```bash
    $ kubectl get pods -l app=antenna-kafka
    ```

    Expected output:
    ```
    NAME               READY   STATUS    RESTARTS   AGE
    antenna-kafka-0    1/1     Running   0          2m
    ```

3. **Check pod logs for any errors**

    ```bash
    $ kubectl logs -l app=antenna-postgres --tail=50
    $ kubectl logs -l app=antenna-kafka --tail=50
    ```

## Creating Kafka Topics

Create the required Kafka topics for event processing:

```bash
$ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-topics \
    --bootstrap-server antenna-kafka:9092 \
    --command-config /etc/kafka/clients/client.properties \
    --create --topic antenna.raw_2_ssf.event.queue --partitions 15
```

```bash
$ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-topics \
    --bootstrap-server antenna-kafka:9092 \
    --command-config /etc/kafka/clients/client.properties \
    --create --topic antenna.ssf_2_action.event.queue --partitions 10
```

**Verify topics were created:**

```bash
$ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-topics \
    --bootstrap-server antenna-kafka:9092 \
    --command-config /etc/kafka/clients/client.properties --list
```

## Troubleshooting

### PostgreSQL Pod Not Starting

**Symptoms**: PostgreSQL pod remains in `Pending` or `CrashLoopBackOff` state.

**Solutions**:

1. Check pod logs for errors:
   ```bash
   $ kubectl logs -l app=antenna-postgres
   ```

2. Verify the PersistentVolumeClaim is bound:
   ```bash
   $ kubectl get pvc
   ```

3. Check certificate file permissions:
   ```bash
   $ kubectl exec antenna-postgres-0 -- ls -la /var/pg/cert/
   ```

### Kafka Pod Not Starting

**Symptoms**: Kafka pod remains in `Pending` or `CrashLoopBackOff` state.

**Solutions**:

1. Check pod logs for errors:
   ```bash
   $ kubectl logs -l app=antenna-kafka
   ```

2. Verify keystore passwords are configured correctly:
   ```bash
   $ kubectl get secret antenna-kafka-cert -o jsonpath='{.data.keystore_password}' | base64 -d
   ```

3. Verify the CLUSTER_ID is set:
   ```bash
   $ kubectl get configmap antenna-kafka-env -o yaml | grep CLUSTER_ID
   ```

### Cannot Create Kafka Topics

**Symptoms**: Topic creation commands fail with authentication or connection errors.

**Solutions**:

1. Verify the Kafka pod is running:
   ```bash
   $ kubectl get pods -l app=antenna-kafka
   ```

2. Verify the client configuration file exists:
   ```bash
   $ kubectl exec antenna-kafka-0 -- cat /etc/kafka/clients/client.properties
   ```

3. Test Kafka connectivity:
   ```bash
   $ kubectl exec antenna-kafka-0 -- /usr/bin/kafka-broker-api-versions \
       --bootstrap-server antenna-kafka:9092 \
       --command-config /etc/kafka/clients/client.properties
   ```

### Certificate Errors

**Symptoms**: SSL/TLS handshake failures or certificate validation errors.

**Solutions**:

1. Verify certificate validity and expiration:
   ```bash
   $ openssl x509 -in configs/keys/postgres.pem -text -noout
   $ openssl x509 -in configs/keys/kafka.pem -text -noout
   ```

2. Verify Subject Alternative Names (SAN) are correct:
   ```bash
   $ openssl x509 -in configs/keys/kafka.pem -text -noout | grep -A1 "Subject Alternative Name"
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

# Check resource usage
$ kubectl top pods
$ kubectl top nodes

```
