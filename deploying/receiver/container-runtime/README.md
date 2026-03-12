# IBM Verify Antenna Receiver on a Container Runtime

This guide provides step-by-step instructions for deploying an IBM Verify Antenna Receiver on a container runtime like Docker or Podman.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [Setting Up the Local Directory](#setting-up-the-local-directory)
  - [Generating Keys and Certificates](#generating-keys-and-certificates)
  - [Creating Action Handlers](#creating-action-handlers)
  - [Configuring TLS for Transmitter Connections](#configuring-tls-for-transmitter-connections)
  - [Copying Datastore Certificates and Secrets](#copying-datastore-certificates-and-secrets)
  - [Setting Up Environment Variables](#setting-up-environment-variables)
- [Running the Receiver](#running-the-receiver)
- [Verifying Receiver Deployment](#verifying-receiver-deployment)
  - [Using IBM Verify Tenant to Authorize Requests](#using-ibm-verify-tenant-to-authorize-requests)
- [Troubleshooting](#troubleshooting)
  - [Receiver Container Not Starting](#receiver-container-not-starting)
  - [Action Handler Errors](#action-handler-errors)
  - [Certificate Errors](#certificate-errors)
  - [General Troubleshooting Commands](#general-troubleshooting-commands)

## Overview

The IBM Verify Antenna Receiver receives and processes security events from transmitters using the OpenID Shared Signals Framework (SSF). It supports various event types including session revocation, credential changes, device compliance changes, and custom event types.

## Prerequisites

- A container runtime like Docker or Podman installed
- **openssl**: For generating SSL/TLS certificates

## Configuration

### Setting Up the Local Directory

> 📘 **Note**
>
> Skip this section if you already cloned the GitHub repository.

If you did not clone the repository, copy the entire `deploying/receiver/container-runtime` directory to your local system. All commands from this point onwards will be executed from this directory.

**Expected Directory Structure:**

```
container-runtime/
├── configs/
│   ├── custom_events.yml
│   ├── js/
│   │   └── (action handlers)
│   ├── keys/
│   │   └── (certificates will be generated here)
│   ├── receiver.yml
│   └── storage.yml
├── docker-compose.yml
└── dotenv
```

### Generating Keys and Certificates

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

Replace `<hostname>` with your actual hostname, or use `antenna-receiver` for internal communication.

### Creating Action Handlers

Action handlers process different event types and execute specific actions based on event data. A sample action handler that logs event details to standard output is provided in `log_event.js` within the `configs/js` directory.

Add custom action handler files to this directory as required for your use case.

### Configuring TLS for Transmitter Connections

If the Receiver must connect to a Transmitter that uses a non-standard or self-signed CA certificate, complete the following steps:

1. **Obtain the transmitter's public certificate** by accessing the transmitter's `/.well-known/ssf-configuration` endpoint and exporting the certificate.

2. **Create a `ca-bundle.pem` file** in the `configs/keys` directory.

3. **Add the public certificate** to the `ca-bundle.pem` file.

4. **Add the environment variable** in the `docker-compose.yml` file to configure the receiver to use the custom CA bundle. Add this under the service at the same level as `env_file`:

    ```yaml
    environment:
      - SSL_CERT_FILE=/var/antenna/config/keys/ca-bundle.pem
    ```

### Copying Datastore Certificates and Secrets

The receiver needs access to the datastore certificates and credentials created during datastore deployment.

> 📘 **Prerequisites**
>
> - The datastore must be fully deployed and configured first (see [Datastore Deployment Guide](../../datastore/container-runtime/README.md))
> - The datastore `.env` file must exist (created from `dotenv` template during datastore setup)
> - The following commands assume the datastore is in `../../datastore/container-runtime/` relative to the current directory

1. Copy the CA certificates from the datastore deployment:

    ```bash
    $ cp ../../datastore/container-runtime/configs/keys/ca.pem configs/keys/pgsql_ca.pem
    $ cp ../../datastore/container-runtime/configs/keys/ca.pem configs/keys/kafka_ca.pem
    ```

2. Create the secrets directory and copy credentials from the datastore `.env` file:

    ```bash
    $ mkdir -p configs/secrets
    
    # Verify the datastore .env file exists
    $ test -f ../../datastore/container-runtime/.env || { echo "Error: Datastore .env file not found. Deploy datastore first."; exit 1; }
    
    # Source the datastore environment and create secret files
    $ source ../../datastore/container-runtime/.env
    $ echo -n "${POSTGRES_USER}" > configs/secrets/pgsql_user
    $ echo -n "${POSTGRES_PASSWORD}" > configs/secrets/pgsql_password
    $ echo -n "${KAFKA_CLIENT_USERS}" > configs/secrets/kafka_user
    $ echo -n "${KAFKA_CLIENT_PASSWORDS}" > configs/secrets/kafka_password
    ```

    If the datastore is in a different location, adjust the paths accordingly.

### Setting Up Environment Variables

1. Copy [dotenv](./dotenv) to `.env` file:

    ```bash
    $ cp dotenv .env
    ```

2. Modify the properties in `.env` file as needed:
   - `HOSTNAME`: The hostname for the receiver
   - `PORT`: The port to expose the receiver on (default: 9043)

## Running the Receiver

1. Ensure all certificates and configuration files are in place.

2. Ensure the datastore is running and the `antenna-network` Docker network exists. If the datastore is not yet deployed, follow the [Datastore Deployment Guide](../datastore/container-runtime/README.md) first.

3. Start the receiver with Docker Compose:

    ```bash
    $ docker-compose up -d
    ```

   The receiver will be available on the port specified in the `.env` file via HTTPS. It will connect to PostgreSQL and Kafka using the hostnames `antenna-postgres` and `antenna-kafka` on the shared `antenna-network`.

## Verifying Receiver Deployment

1. **Verify the container is running:**

    ```bash
    $ docker-compose ps antenna-receiver
    ```

    Expected output:
    ```
    NAME               IMAGE                                              STATUS
    antenna-receiver   icr.io/ibm-verify/ibm-verify-antenna-receiver:...  Up
    ```

2. **Check container logs for errors:**

    ```bash
    $ docker-compose logs antenna-receiver
    ```

3. **Test connectivity** by opening a web browser and navigating to `https://localhost:<PORT>/mgmt/v1.0/receivers/config` (replace `<PORT>` with your configured port).

4. **Register a stream** with a SSF-compliant transmitter by using one of the [scripts](../scripts).

### Using IBM Verify Tenant to Authorize Requests

If connecting to a transmitter authorized by IBM Verify OIDC provider:

1. Create a new API client in IBM Verify using the instructions in the [IBM Verify documentation](https://www.ibm.com/docs/en/security-verify?topic=access-creating-api-clients). No entitlements are required.
   - **Note**: The UI currently requires selecting an entitlement during creation. Select any entitlement, save the client, then edit and remove the entitlement.

2. Use these client credentials directly or generate an access token, depending on the script you use in [scripts](../scripts).

## Troubleshooting

### Receiver Container Not Starting

**Symptoms**: Receiver container exits immediately or shows errors in logs.

**Solutions**:

1. Check container logs:
   ```bash
   $ docker-compose logs antenna-receiver
   ```

2. Verify certificate files exist and have correct permissions:
   ```bash
   $ ls -la configs/keys/
   ```

3. Ensure the `.env` file has valid configuration.

4. Verify the datastore (PostgreSQL and Kafka) is running if using external datastore.

### Action Handler Errors

**Symptoms**: Events are received successfully but action processing fails.

**Solutions**:

1. Check receiver logs for JavaScript errors:
   ```bash
   $ docker-compose logs antenna-receiver | grep -i error
   ```

2. Verify action handler files exist:
   ```bash
   $ ls -la configs/js/
   ```

3. Validate action handler syntax locally before deploying.

### Certificate Errors

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

3. If using custom CA bundle, ensure it's properly configured in docker-compose.yml.

4. Regenerate certificates if they are expired or contain incorrect information.

### General Troubleshooting Commands

```bash
# View all containers
$ docker-compose ps

# Check container logs
$ docker-compose logs <service-name> --tail=100 -f

# Restart a specific service
$ docker-compose restart <service-name>

# Stop all services
$ docker-compose down

# Remove volumes (WARNING: This will delete all data)
$ docker-compose down -v
```
