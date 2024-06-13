# mongodb-tools

Go-based tools for MongoDB container orchestration.

NOTE: This is a hard fork of https://github.com/percona/mongodb-orchestration-tools

**Tools**:
- **mongodb-healthcheck**: a tool for running Kubernetes liveness check

## Required

### MongoDB
These tools were designed/tested for use with [Percona Server for MongoDB](https://www.percona.com/software/mongo-database/percona-server-for-mongodb) 5.0 and above with [Replication](https://docs.mongodb.com/manual/replication/) and [Authentication](https://docs.mongodb.com/manual/core/authentication/) enabled.

## Build
1. Install go1.22+ and 'make'
2. Run 'make k8s'
3. Find binaries in 'bin' directory
