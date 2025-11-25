#!/bin/sh
#
# Custom entrypoint to set some StatefulSet Pod environment variables
# before the actual entrypoint runs.
#

# broker username password
export KAFKA_LISTENER_NAME_BROKER_PLAIN_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"admin\" password=\"admin-secret\" user_${KAFKA_CLIENT_USERS}=\"${KAFKA_CLIENT_PASSWORDS}\" ;"

# controller username password
export KAFKA_LISTENER_NAME_CONTROLLER_PLAIN_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${KAFKA_CONTROLLER_USER}\" password=\"${KAFKA_CONTROLLER_PASSWORD}\" user_${KAFKA_CONTROLLER_USER}=\"${KAFKA_CONTROLLER_PASSWORD}\" ;"

# Figure out my Pod ID from the StatefulSet hostname
echo hostname $(hostname)
echo $(hostname | grep -Eo '[0-9]+$' | tail -1)
# __POD_ID__=$(hostname | perl -ne 'print $1 if(/\-(\d+)$/)')
__POD_ID__=$(hostname | grep -Eo '[0-9]+$' | tail -1)
echo __POD_ID__ "${__POD_ID__}"

# Set the Kafka Node and Broker IDs
export KAFKA_BROKER_ID="${__POD_ID__}"
echo KAFKA_BROKER_ID "${KAFKA_BROKER_ID}"
export KAFKA_CFG_NODE_ID="${__POD_ID__}"
echo KAFKA_CFG_NODE_ID "${KAFKA_CFG_NODE_ID}"
export KAFKA_NODE_ID="${__POD_ID__}"
echo KAFKA_NODE_ID "${KAFKA_NODE_ID}"

# Set the Pod specific advertised listener
export KAFKA_ADVERTISED_LISTENERS="BROKER://antenna-kafka-${__POD_ID__}.antenna-kafka:9092"

echo $KAFKA_ADVERTISED_LISTENERS

# Now call the entry point proper
exec /etc/confluent/docker/run