yum install -y docker-ce docker-ce-cli containerd.io
groupadd docker
usermod -a -G docker jdoe1
systemctl enable docker
systemctl start docker
docker pull registry.access.redhat.com/ubi7/ubi
docker pull postgres:13.1

# All nodes (including manager)
firewall-cmd  --add-port=2376/tcp --add-port=7946/tcp --add-port=7946/udp --add-port=4789/udp
firewall-cmd --runtime-to-permanent

# Manager only (registry and docker swarm)
firewall-cmd --add-port=2377/tcp --add-port=5001/tcp
firewall-cmd --runtime-to-permanent

# Manager only
docker swarm init --advertise-addr 192.168.2.90

# Minon nodes only
docker swarm join --token SWMTKN-1-52ajuc1cgdxvs66cg7cyi5lzikszevwwfgq5sykwlh1pvwfmse-cspwa1cijmtkzua5vm9ttj4in 192.168.2.90:2377

# Manager only
docker node ls # should show manager and minons as active (if not check firewalls)

# Add constraint label to host where database must remain on
docker node update --label-add database=true ds01.demolab.com 

# Setup registry and push custom image to registry
# Assumes this is on master

# Create custom CA and signed certificates
mkdir certs
cd certs
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out registry.key
chmod 600 registry.key
openssl req -new -key registry.key -out registry.csr
openssl x509 -req -days 365 -in registry.csr -signkey registry.key -out registry.crt

# Install CA (perform on both hosts)
sudo cp registry.crt /etc/pki/ca-trust/
sudo update-ca-trust
sudo mkdir -p /etc/docker/certs.d/ds01.demolab.com:5001
sudo cp registry.crt /etc/docker/certs.d/ds01.demolab.com:5001/ca.crt
sudo systemctl restart docker

# Create a user account
mkdir auth
docker pull httpd:2.4
docker run --rm \
  --entrypoint htpasswd \
  httpd:2.4 -Bbn jdoe1 testerpass > auth/htpasswd

# Create the registry container
docker pull registry:2
docker volume create image-registry 
docker run -d -p 5001:443 --name registry \
       --restart=always -v image-registry:/var/lib/registry \
       -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
       -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
       -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
       -v /home/jdoe1/test/certs:/certs \
       -e "REGISTRY_AUTH=htpasswd" \
       -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
       -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
       -v /home/jdoe1/test/auth:/auth \
       registry:2

# Login to the registry (perform on both hosts)
# Make sure hostname for registry host is in DNS or in /etc/hosts
docker login ds01.demolab.com:5001

# Create the sleep image (with psql for testing) and 
# push it to the registry
docker build -t ds01.demolab.com:5001/sleep:1.0.0 .
docker push ds01.demolab.com:5001/sleep:1.0.0

# Push the database container to simplify
docker tag postgres:13.1 ds01.demolab.com:5001/postgres:13.1
docker push ds01.demolab.com:5001/postgres:13.1

# Remove all images except the registry to start with a clean slate
docker rmi $(docker images -n)

# Deploy the docker-compose (or docker stack) setup
# Note: with-registry-auth is required for the private registry to work
#       and each worker must have run "docker login" as well. 
docker stack deploy -c docker-compose.yml --with-registry-auth testdeploy
docker stack ls
docker stack ps testdeploy

# Scenarios tested:
# 1. Restarting the database container multiple times proves that the container
#    stays tied to the host with the database=true label
# 2. Restarting the test web container multiple times proves it moves between hosts
#    and is not restricted to any one host (no constraints)
# 3. Connecting to the web container while on the same host as the database
#    and confirmed that the "database" service name alias works as a hostname
#    for psql. 
# 4. Connecting to the web container while on a different host than the database
#    and confirmed that the "database" service name alias works as a hostname for
#    psql. 
# 5. Confirmed that database persistent volume is keep when the database container 
#    dies (e.g. stopped via docker stop). 
# 6. Removed stack deployment and validated that database volume remains
# 7. Validated registry access from all workers. 
# 8. Validated that 'docker stack rm testdeploy' does not remove persistent volume
#    and that a re-deployment of the stack with the same name re-uses the same volume


# Notes:
# To access the database container in a script (e.g. to perform backup) use:
docker exec -it $(docker container ls | grep testdeploy_database | awk '{print $1}') psql -h localhost -U jdoe1
