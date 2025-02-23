#!/bin/bash

# ===== SETUP

setup() {
  load ../load/base.bash
  load ../load/orchestrator.bash
  load_bats_ext
  setup_home_dir
  skip_if_orchestrator_tests_not_enabled
  copy_enrolled_home_dir
}

teardown() {
  teardown_home_dir
}

# ===== TESTS

@test "nodes - create with config, admin enrolling twice with the project doesn't return error" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"

  cat <<EOF >"$OCKAM_HOME/config.yaml"
name: n1
EOF

  ## The default identity is already enrolled, so the enrollment step should be skipped
  run_success "$OCKAM" node create "$OCKAM_HOME/config.yaml" \
    --enrollment-ticket "$OCKAM_HOME/enrollment.ticket"
  run_success "$OCKAM" message send hello --timeout 5 --to "/node/n1/secure/api/service/echo"
}

@test "nodes - create with config, non-admin enrolling twice with the project doesn't return error" {
  ADMIN_HOME_DIR="$OCKAM_HOME"
  ticket_path="$ADMIN_HOME_DIR/enrollment.ticket"
  export RELAY_NAME=$(random_str)
  $OCKAM project ticket --usage-count 5 --relay $RELAY_NAME >"$ticket_path"

  # User: try to enroll the same identity twice
  setup_home_dir
  export CLIENT_PORT=$(random_port)

  ## First time it works
  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.basic.config.yaml" \
    --enrollment-ticket "$ticket_path" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT"
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"

  ## Second time it will skip the enrollment step and the node will be set up as expected
  run_success "$OCKAM" node delete --all -y
  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.basic.config.yaml" \
    --enrollment-ticket "$ticket_path" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT"
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"
}

@test "nodes - create with config in foreground" {
  # Admin: create enrollment ticket
  ADMIN_HOME_DIR="$OCKAM_HOME"
  ticket_path="$ADMIN_HOME_DIR/enrollment.ticket"
  export RELAY_NAME=$(random_str)
  $OCKAM project ticket --usage-count 5 --relay $RELAY_NAME >"$ticket_path"

  # User: create a node in the foreground with a portal and using an enrollment ticket
  setup_home_dir
  export CLIENT_PORT=$(random_port)

  ## Create node and try to reach it
  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.basic.config.yaml" \
    --foreground \
    --enrollment-ticket "$ticket_path" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT" &
  sleep 10
  run_success "$OCKAM" message send hello --timeout 2 --to "/node/n1/secure/api/service/echo"
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"
}

@test "nodes - create with config, single machine, unnamed portal" {
  export RELAY_NAME=$(random_str)
  export NODE_PORT=$(random_port)
  export CLIENT_PORT=$(random_port)

  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.1.unnamed-portal.config.yaml" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT"

  # node created with expected name
  run_success "$OCKAM" message send --timeout 5 hello --to "/node/n1/secure/api/service/echo"
  # tcp-listener-address set to expected port
  run_success "$OCKAM" message send --timeout 5 hello --to "/dnsaddr/127.0.0.1/tcp/$NODE_PORT/secure/api/service/echo"
  # portal is working: inlet -> relay -> outlet -> python server
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"
}

@test "nodes - in-memory, create with config, single machine, unnamed portal" {
  ADMIN_HOME_DIR="$OCKAM_HOME"
  ticket_path="$ADMIN_HOME_DIR/enrollment.ticket"
  export RELAY_NAME=$(random_str)
  $OCKAM project ticket --usage-count 5 --relay $RELAY_NAME >"$ticket_path"

  setup_home_dir
  export NODE_PORT=$(random_port)
  export CLIENT_PORT=$(random_port)
  OCKAM_SQLITE_IN_MEMORY=true "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.1.unnamed-portal.config.yaml" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT" --enrollment-ticket $ticket_path -f &
  pid=$!
  sleep 5

  # portal is working: inlet -> relay -> outlet -> python server
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"

  kill -9 $pid
}

@test "nodes - create with config, single machine, named portal" {
  export RELAY_NAME=$(random_str)
  export CLIENT_PORT=$(random_port)
  export NODE_PORT=$(random_port)

  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.2.named-portal.config.yaml" \
    --variable SERVICE_PORT="$PYTHON_SERVER_PORT"

  # node created with expected name
  run_success "$OCKAM" message send --timeout 5 hello --to "/node/n1/secure/api/service/echo"
  # tcp-listener-address set to expected port
  run_success "$OCKAM" message send --timeout 5 hello --to "/dnsaddr/127.0.0.1/tcp/$NODE_PORT/secure/api/service/echo"
  # portal is working: inlet -> relay -> outlet -> python server
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CLIENT_PORT"
}

@test "nodes - create with config, multiple machines" {
  skip "Temporary disabled due to some upcoming changes in the dev env of the Orchestrator"
  ADMIN_HOME_DIR="$OCKAM_HOME"
  export SAAS_RELAY_NAME=$(random_str)
  # Admin: create enrollment ticket for SaaS
  $OCKAM project ticket \
    --attribute "ockam-role=enroller" --attribute "to-saas=outlet" --attribute "from-saas=inlet" \
    --relay "to-$SAAS_RELAY_NAME" --usage-count 10 >"$ADMIN_HOME_DIR/saas.ticket"

  # SaaS: create portal + enrollment ticket for Customer
  setup_home_dir
  SAAS_HOME_DIR="$OCKAM_HOME"

  ## The portal ports are constants in the SaaS machine, so we can export them
  export SAAS_INLET_PORT=$(random_port)
  export SAAS_OUTLET_PORT=$PYTHON_SERVER_PORT

  ## The customer details are variables that will change everytime the SaaS wants to add a new customer
  customer_name=$(random_str)
  customer_service="myapp"

  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.3.saas.config.yaml" \
    --enrollment-ticket "$ADMIN_HOME_DIR/saas.ticket" \
    --variable CUSTOMER="$customer_name" \
    --variable CUSTOMER_SERVICE_NAME="$customer_service"

  $OCKAM project ticket \
    --attribute "to-saas=inlet" --attribute "from-saas=outlet" \
    --relay "to-$customer_name" --usage-count 10 >"$SAAS_HOME_DIR/$customer_name.ticket"

  # Customer: create portal
  setup_home_dir

  ## Similarly, we export the constant variables for the Customer
  export CUSTOMER="$customer_name"
  export CUSTOMER_INLET_PORT=$(random_port)
  export CUSTOMER_OUTLET_PORT=$(random_port)
  export CUSTOMER_SERVICE_NAME="$customer_service"

  run_success "$OCKAM" node create "$BATS_TEST_DIRNAME/fixtures/node-create.3.customer.config.yaml" \
    --enrollment-ticket "$SAAS_HOME_DIR/$customer_name.ticket"

  # Test: SaaS service can be reached from Customer's inlet
  $OCKAM message send hi --to "/project/default/service/forward_to_to-$SAAS_RELAY_NAME/secure/api/service/echo"
  run_success curl -sfI --retry-all-errors --retry-delay 5 --retry 10 -m 5 "127.0.0.1:$CUSTOMER_INLET_PORT"

  # Test: Customer node can be reached from SaaS's side
  export OCKAM_HOME="$SAAS_HOME_DIR"
  $OCKAM message send hi --to "/project/default/service/forward_to_to-$CUSTOMER/secure/api/service/echo"
}

@test "nodes - create with config, download config and enrollment-ticket from URL" {
  random_file_name=$(random_str)
  ticket_relative_path=".tmp/$random_file_name.ticket"
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME_BASE/$ticket_relative_path"

  # Create a config file in the python server's root directory
  config_relative_path=".tmp/$random_file_name.config.yaml"
  cat <<EOF >"$OCKAM_HOME_BASE/$config_relative_path"
name: n1
EOF

  # Using a proper url (with scheme)
  setup_home_dir
  run_success "$OCKAM" node create "http://127.0.0.1:$PYTHON_SERVER_PORT/$config_relative_path" \
    --enrollment-ticket "http://127.0.0.1:$PYTHON_SERVER_PORT/$ticket_relative_path"
  run_success "$OCKAM" message send --timeout 5 hello --to "/node/n1/secure/api/service/echo"

  # Without a scheme
  setup_home_dir
  run_success "$OCKAM" node create "127.0.0.1:$PYTHON_SERVER_PORT/$config_relative_path" \
    --enrollment-ticket "127.0.0.1:$PYTHON_SERVER_PORT/$ticket_relative_path"
  run_success "$OCKAM" message send --timeout 5 hello --to "/node/n1/secure/api/service/echo"
}

@test "nodes - create with config, using the specified identity" {
  export RELAY_NAME=$(random_str)
  $OCKAM project ticket --relay "$RELAY_NAME" >"$OCKAM_HOME/enrollment.ticket"
  ticket_path="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  cat <<EOF >"$OCKAM_HOME/config.yaml"
name: n1
identity: i1
relay: $RELAY_NAME
EOF

  # The identity will be created and enrolled
  run_success "$OCKAM" node create "$OCKAM_HOME/config.yaml" \
    --enrollment-ticket "$ticket_path"

  # Use the identity to send a message
  $OCKAM message send hi --identity i1 --to "/project/default/service/forward_to_$RELAY_NAME/secure/api/service/echo"
}

@test "nodes - create with config, using the specified enrollment ticket" {
  $OCKAM project ticket >"$OCKAM_HOME/enrollment.ticket"
  ticket_path="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir

  # The identity will be enrolled
  run_success "$OCKAM" node create n1 --identity i1 --enrollment-ticket "$ticket_path"

  # Check that the identity can reach the project
  run_success $OCKAM message send hi --identity i1 --to "/project/default/service/echo"
}

@test "nodes - create with config, using the specified enrollment ticket, overriding config" {
  $OCKAM project ticket >"$OCKAM_HOME/enrollment.ticket"
  ticket_path="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  cat <<EOF >"$OCKAM_HOME/config.yaml"
ticket: other.ticket
name: n2
identity: i2
EOF

  # The values from the config file will be overridden by the command line arguments
  run_success "$OCKAM" node create n1 --identity i1 --enrollment-ticket "$ticket_path"
  run_failure "$OCKAM" node show n2
  run_failure "$OCKAM" identity show i2

  # Check that the identity can reach the project
  run_success $OCKAM message send hi --identity i1 --to "/project/default/service/echo"
}

@test "nodes - create with config, using the specified enrollment ticket as an env var" {
  $OCKAM project ticket >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET=$(cat "$OCKAM_HOME/enrollment.ticket")

  setup_home_dir
  # The ENROLLMENT_TICKET is parsed automatically, so the `node create` command will
  # first use the ticket before creating the node
  run_success "$OCKAM" node create n1
  run_success "$OCKAM" node show n1

  # Check that the identity can reach the project
  run_success $OCKAM message send hi --to "/project/default/service/echo"
}

@test "nodes - create with config, using the specified enrollment ticket as an env var, in foreground" {
  $OCKAM project ticket >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET=$(cat "$OCKAM_HOME/enrollment.ticket")

  setup_home_dir
  run_success "$OCKAM" node create n1 -f &
  sleep 10
  run_success "$OCKAM" node show n1

  # Check that the identity can reach the project
  run_success $OCKAM message send hi --to "/project/default/service/echo"
}

@test "nodes - create with config, using a json-encoded enrollment ticket" {
  $OCKAM project ticket --output json >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  cat <<EOF >"$OCKAM_HOME/config.yaml"
ticket: ${ENROLLMENT_TICKET}
name: n1
EOF

  run_success "$OCKAM" node create "$OCKAM_HOME/config.yaml"
  run_success "$OCKAM" node show n1

  # Check that the identity can reach the project
  run_success $OCKAM message send hi --to "/project/default/service/echo"
}

@test "nodes - create node with both tcp and influx inlets" {
  tcp_inlet_port="$(random_port)"
  influxdb_inlet_port="$(random_port)"
  cat <<EOF >"$OCKAM_HOME/node.yaml"
name: n1

tcp-inlet:
  from: 0.0.0.0:${tcp_inlet_port}
  no-connection-wait: true

influxdb-inlet:
  from: 0.0.0.0:${influxdb_inlet_port}
  leased-token-strategy: shared
  no-connection-wait: true
EOF

  # We just want to check that the command doesn't fail
  run_success "$OCKAM" node create "$OCKAM_HOME/node.yaml"
}

@test "nodes - create with inline config 1" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{  \"name\": \"n1\" }"
  run_success "$OCKAM" node show n1
  run_success $OCKAM message send hi --from n1 --to "/project/default/service/echo"
}

@test "nodes - create with inline config 2" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{ \"ticket\": \"$ENROLLMENT_TICKET\", \"name\": \"n2\" }"
  run_success "$OCKAM" node show n2
  run_success $OCKAM message send hi --from n2 --to "/project/default/service/echo"
}

@test "nodes - create with inline config 3" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  ticket_path="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{ \"name\": \"n3\" }" --enrollment-ticket "$ticket_path"
  run_success "$OCKAM" node show n3
  run_success $OCKAM message send hi --from n3 --to "/project/default/service/echo"
}

@test "nodes - create with inline config 4" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{  \"name\": \"n4\" }" --foreground &
  sleep 10
  run_success "$OCKAM" node show n4
  run_success $OCKAM message send hi --from n4 --to "/project/default/service/echo"
}

@test "nodes - create with inline config 5" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  export ENROLLMENT_TICKET="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{ \"ticket\": \"$ENROLLMENT_TICKET\", \"name\": \"n5\" }" --foreground &
  sleep 10
  run_success "$OCKAM" node show n5
  run_success $OCKAM message send hi --from n5 --to "/project/default/service/echo"
}

@test "nodes - create with inline config 6" {
  $OCKAM project ticket --usage-count 5 >"$OCKAM_HOME/enrollment.ticket"
  ticket_path="$OCKAM_HOME/enrollment.ticket"

  setup_home_dir
  run_success "$OCKAM" node create "{ \"name\": \"n6\" }" --enrollment-ticket "$ticket_path" --foreground &
  sleep 10
  run_success "$OCKAM" node show n6
  run_success $OCKAM message send hi --from n6 --to "/project/default/service/echo"
}
