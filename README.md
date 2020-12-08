# Docker Swarm - Environment Setup & Testing

This repository creates a 2-node docker swarm environment for testing. To validated
the swarm is working correctly this setup creates a single container as a postgres client
and a postgres database. The database is locked to the master node to allow it to use a persistent local storage volume while the postgres client is not locked to any host. Once
running the swarm services will allow the hosts to communicate with each other using their
service names (e.g. database for the database container). 

## Requirements

* RedHat/CentOS 7
* Docker CE Repository installed
* User account (e.g. jdoe1) setup
