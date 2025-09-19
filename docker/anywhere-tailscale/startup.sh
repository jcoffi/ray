#!/bin/bash
export HOME=/home/ray

if [ -z "$TSAPIKEY" ]; then
  echo "Environmental variable for TSAPIKEY not set"
  exit 1
fi

curl -fsSLZ -o /home/ray/run_tests.sh "https://raw.githubusercontent.com/jcoffi/ray/cluster-anywhere/docker/anywhere-tailscale/run_tests.sh"
sudo chmod +x /home/ray/run_tests.sh


echo "healthy" | sudo tee /tmp/health_status.html
if [ ! -f /tmp/index.html ]; then
  ln -s /tmp/health_status.html /tmp/index.html
fi
#needed for the custom healthcheck until such time as I move over to k8s
python3 -m http.server 80 --directory /tmp --bind 0.0.0.0 > output.log 2>&1 &

echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "vm.max_map_count = 262144" | sudo tee -a /etc/sysctl.conf
# echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.conf

# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
sudo mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH $TS_STATEDIR
sudo chgrp -R crate /crate
sudo chgrp -R crate /data
sudo chown -R 1000 $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH $TS_STATEDIR
sudo chmod -R 774 /data
sudo chmod -R 774 $TS_STATEDIR

## Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS


#echo "export NUMEXPR_MAX_THREADS='$(nproc)'" | sudo tee -a ~/.bashrc
echo "export MAKEFLAGS='-j$(nproc)'" | sudo tee -a ~/.bashrc
echo "export CPU_COUNT='$(nproc)'" | sudo tee -a ~/.bashrc

memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert kB to GB
gb_memory=$(echo "scale=2; $memory / 1048576" | bc)
shm_memory=$(echo "scale=0; $gb_memory / 1" | bc)


# Convert to B from kB and set size at 80% of total memory
ray_object_store=$(echo "scale=0; $memory * 1024 * .40 / 1" | bc)


#settings number of cpus for optimial (local) speed
#export NUMEXPR_MAX_THREADS="$(nproc)"
#used by conda to specify cpus for building packages
export MAKEFLAGS="-j$(nproc)"
#used by conda
export CPU_COUNT="$(nproc)"
#https://docs.cupy.dev/en/stable/reference/environment.html#:~:text=%5B%3A%5D%20%3D%20numpy_ndarray-,CUPY_ACCELERATORS,-%23
#export CUPY_ACCELERATORs=cub,cutensor,cutensornet



#CRATE_HEAP_SIZE=$(echo $shm_memory | awk '{print int($0+0.5)}')
export CRATE_HEAP_SIZE="${shm_memory}G"
export shm_memory="${shm_memory}G"
export ray_object_store=${ray_object_store}

#Disabled the TLS for ray because it requires the port in the cert name.
export RAY_USE_TLS=0
export RAY_TLS_SERVER_CERT=/data/certs/${HOSTNAME,,}.chimp-beta.ts.net.crt
export RAY_TLS_SERVER_KEY=/data/certs/${HOSTNAME,,}.chimp-beta.ts.net.key

#if [ ! -f /data/certs/lets-encrypt-r3.crt ]; then
sudo curl -s https://letsencrypt.org/certs/lets-encrypt-r3.pem -o /data/certs/lets-encrypt-r3.crt \
&& sudo chmod 777 /data/certs/lets-encrypt-r3.crt
#fi
export RAY_TLS_CA_CERT=/data/certs/lets-encrypt-r3.crt

#putting the key in the same bucket were granting access to using that key is incredibly stupid. yet, here we are.
KEY_STORAGE_URL="https://storage.googleapis.com/cluster-anywhere/files/cluster-anywhere-26784947a5ae.json"

# Specify the local path where the key should be stored
LOCAL_KEY_PATH="/data/cluster-anywhere-26784947a5ae.json"

# Download the key from cloud storage
curl -o ${LOCAL_KEY_PATH} ${KEY_STORAGE_URL}

# Set the environment variable for Google Application Credentials
export GOOGLE_APPLICATION_CREDENTIALS=${LOCAL_KEY_PATH}



check_cloud_provider() {

  # Check Google Cloud Platform (GCP)
  if curl -s -m 5 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/) != "404" ]; then
      #echo "Cloud Provider: Google Cloud Platform (GCP)"
      location="GCP"
      export LOCATION=$location
      echo $location
      return
    fi
  fi
  # We check GCP first because basically both AWS and GCP search for the same initial curl URL. But there are specific values that only GCP uses.
  # In the future this whole function should be cleaned up.
  # Check AWS EC2
  if curl -s -m 5 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 http://169.254.169.254/latest/meta-data/) != "404" ]; then
      #echo "Cloud Provider: Amazon Web Services (AWS)"
      location="AWS"
      export LOCATION=$location
      echo $location
      return
    fi
  fi

  # Check Microsoft Azure
  if curl -s -m 5 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01) != "404" ]; then
      #echo "Cloud Provider: Microsoft Azure"
      location="Azure"
      export LOCATION=$location
      echo $location
      return
    fi
  fi

  # Check Oracle Cloud Infrastructure (OCI)
  if curl -s -m 5 http://169.254.169.254/opc/v1/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 http://169.254.169.254/opc/v1/) != "404" ]; then
      #echo "Cloud Provider: Oracle Cloud Infrastructure (OCI)"
      location="OCI"
      export LOCATION=$location
      echo $location
      return
    fi
  fi

  # Check RunPod
  if [ $RUNPOD_API_KEY ]; then
    #echo "Cloud Provider: RunPod"
    location="RunPod"
    export LOCATION=$location
    echo $location
    return
  fi

  # Check Vast
  if [ $VAST_CONTAINERLABEL ]; then
    #echo "Cloud Provider: Vast.ai"
    location="Vast"
    export LOCATION=$location
    echo $location
    return
  fi

  # Default fallback
  #echo "Unable to determine the Cloud Provider. Either it's a new CSP or it's OnPrem"
  location="OnPrem"
  export LOCATION=$location
  echo $location
}



# Invoke the function
if ! grep -q "LOCATION=" /etc/environment; then
  echo "LOCATION=$(check_cloud_provider)" | sudo tee -a /etc/environment
fi
export $(grep "LOCATION=" /etc/environment)


functiontodetermine_cpu() {
  # Check if lscpu command exists
  if command -v lscpu >/dev/null 2>&1 ; then
      # Get vendor information from lscpu output
      vendor=$(lscpu | grep 'Vendor ID' | awk '{print $3}')

      # Check if vendor is AMD or Intel
      if [ "$vendor" == "AuthenticAMD" ]; then
        export CPU_VENDOR=$vendor
        echo $vendor
      elif [ "$vendor" == "GenuineIntel" ]; then
        export CPU_VENDOR=$vendor
        echo $vendor
      else
        echo "Unknown"
      fi
  fi
}


if ! grep -q "CPU_VENDOR=" /etc/environment; then
  echo "CPU_VENDOR=$(functiontodetermine_cpu)" | sudo tee -a /etc/environment
fi
export $(grep "CPU_VENDOR=" /etc/environment)

#set -ae
sudo chmod 774 -R $TS_STATEDIR/
if [ -d "$TS_STATEDIR/certs/" ] && [ ! -e "/data/certs" ]; then
  cd /data
  sudo ln -s ./tailscale/certs/ certs
  cd ~
  # add in code to search and remove the machine name from tailscale if it already exists
  deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
  export deviceid=$deviceid

  echo "Deleting the device from Tailscale"
  curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"
fi






### getting a list of remaining devices
# Make the GET request to the Tailscale API to retrieve the list of all devices
# This could be updated to grab the DNS domain too to be more flexable.
# This is used for the parameter discovery.seed.hosts in crate.yml
function get_cluster_hosts() {
  #TSAPIKEY=$1

  clusterhosts=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: failed to fetch list of devices from Tailscale API"
    return 1
  fi

  clusterhosts=$(echo $clusterhosts | jq -r '.devices[].name')
  if [ $? -ne 0 ]; then
    echo "Error: failed to parse list of devices from Tailscale API response"
    clusterhosts="nexus:4300"
  fi


  # making it a comma-separated list
  clusterhosts="$(echo $clusterhosts | tr ' ' ',')"
  # removing AWS instances
  clusterhosts="$(echo $clusterhosts | sed 's/i-[^,]*,//g')"
  # strip domain names
  #clusterhosts="$(echo $clusterhosts | sed 's/.chimp-beta.ts.net/:4300/g')"

  echo $clusterhosts
}

export CLUSTERHOSTS="$(get_cluster_hosts)"
#export CLUSTERNODES="$(echo $CLUSTERHOSTS | sed 's/.chimp-beta.ts.net/:4300/g')"

if [ ! -c $TS_STATEDIR ] && echo $CLUSTERHOSTS | grep -q $HOSTNAME ; then
  deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
  export deviceid=$deviceid

  echo "Deleting the device from Tailscale"
  curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"
fi




if [ -c /dev/net/tun ] || [ -c /dev/tun ]; then
    sudo tailscaled -port 41641 -statedir $TS_STATEDIR 2>/dev/null&
    sudo tailscale up --operator=ray --auth-key=$TS_AUTHKEY --accept-dns=true --accept-risk=all --accept-routes --ssh
else
    echo "tun doesn't exist"
    sudo tailscaled -port 41641 -statedir $TS_STATEDIR -tun userspace-networking -state mem: -socks5-server=localhost:1055 -outbound-http-proxy-listen=localhost:1055 2>/dev/null&
    alldevicesips=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq -r '.devices[].addresses[]'| awk '/:/ {print "["$0"]"; next} 1' | paste -sd, -)
    export alldevicesips=$alldevicesips
    discovery_seed_hosts="-Cdiscovery.seed_hosts=$alldevicesips \\"
    #cluster_initial_master_nodes="-Ccluster.initial_master_nodes=$alldevicesips \\"
    sudo tailscale up --operator=ray --auth-key=$TS_AUTHKEY --accept-dns=true --accept-risk=all --accept-routes --ssh
    export socks_proxy=socks5h://localhost:1055/
    export SOCKS_PROXY=socks5h://localhost:1055/
    export ALL_PROXY=socks5h://localhost:1055/
    export http_proxy=http://localhost:1055/
    export HTTP_PROXY=http://localhost:1055/
    export https_proxy=http://localhost:1055/
    export HTTPS_PROXY=http://localhost:1055/
    #thisdevicesips=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .addresses[] | awk '/:/ {print "["$0"]"; next} 1' | paste -sd, -)
    sudo sed -i "s/_tailscale0_/_eth0_/g" /crate/config/crate.yml
    echo 'http.proxy.host:localhost' | sudo tee -a /crate/config/crate.yml
    echo 'http.proxy.port:1055' | sudo tee -a /crate/config/crate.yml
    #export CRATE_JAVA_OPTS="-DsocksProxyHost=localhost -DsocksProxyPort=1055 $CRATE_JAVA_OPTS"
    #export RAY_grpc_enable_http_proxy="1"
fi



# lcase_hostname=${HOSTNAME,,}.chimp-beta.ts.net
# #create cert

# if [ ! -f /data/certs/$lcase_hostname.key ]; then
#    cd /data/certs
#    echo "Creating certs"
#    sudo tailscale cert ${lcase_hostname} &
#    cd $HOME
# fi

# export KEYSTOREPASSWORD=$RANDOM$RANDOM
# #create p12
# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/$lcase_hostname.key ]; then
#     echo "Generating p12"
#     sudo rm -rf /data/certs/keystore.p12
#     cd /data/certs
#     sudo openssl pkcs12 -export -name "$lcase_hostname" -in "$lcase_hostname.crt" -inkey "$lcase_hostname.key" -out keystore.p12 -passout pass:"$KEYSTOREPASSWORD"
#     cd $HOME
# fi
# #create jks
# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/keystore.p12 ]; then
#     echo "Generating jks"
#     sudo rm -rf /data/certs/keystore.jks
#     sudo rm -rf /data/certs/truststore.jks
#     cd /data/certs
#     sudo -E /crate/jdk/bin/keytool -importkeystore -destkeystore /data/certs/keystore.jks -srckeystore /data/certs/keystore.p12 -srcstoretype pkcs12 -alias $lcase_hostname -srcstorepass $KEYSTOREPASSWORD -deststorepass $KEYSTOREPASSWORD
#     wget -nc https://letsencrypt.org/certs/lets-encrypt-r3.pem
#     sudo -E /crate/jdk/bin/keytool -importcert -alias letsencryptint -keystore /data/certs/truststore.jks -file /data/certs/lets-encrypt-r3.pem -trustcacerts -storepass $KEYSTOREPASSWORD
#     cd $HOME
# fi

# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/keystore.jks ]; then
#     echo "ssl.keystore_filepath: /data/certs/keystore.jks" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.keystore_password: $KEYSTOREPASSWORD" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.truststore_filepath: /data/certs/truststore.jks" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.truststore_password: $KEYSTOREPASSWORD" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.transport.mode: on" | sudo tee -a /crate/config/crate.yml \
#     && sudo touch /crate/config/ssl_enabled \
#     && echo $KEYSTOREPASSWORD | sudo tee -a /crate/config/ssl_enabled
# fi

# sudo chmod 774 -R /data/certs


while [ ! $tailscale_status = "Running" ]
    do
        echo "Waiting for tailscale to start..."
        tailscale_status="$(tailscale status -json | jq -r .BackendState)"
done

#current_node_master=$(crash --hosts ${CLUSTERHOSTS} -c "SELECT n.hostname FROM sys.cluster c JOIN sys.nodes n ON c.master_node = n.id;" --format raw | jq -r '.rows[] | .[0]')
#export CURRENTNODEMASTER="$(crash --hosts ${CLUSTERHOSTS} -c "SELECT n.hostname FROM sys.cluster c JOIN sys.nodes n ON c.master_node = n.id;" --format raw | jq -r '.rows[] | .[0]')"

# check if we already have state data
if [ -d "$CRATE_HEAP_DUMP_PATH" ]; then

	if [ -d "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/" ] && [ "$(ls -A $CRATE_HEAP_DUMP_PATH/nodes/0/_state/)" ]; then
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is not Empty"
        crate_state_data=$true
	else
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is Empty"
        crate_state_data=$false
	fi
else
	    echo "Directory $CRATE_HEAP_DUMP_PATH not found."
      exit 1
fi


if [ "$NODETYPE" = "head" ]; then
  node_name='-Cnode.name=nexus \\'
  node_master='-Cnode.master=true \\'
  node_data='-Cnode.data=false \\'


  ray start --head --disable-usage-stats --num-cpus=0 --include-dashboard=True --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net #--system-config='{"object_spilling_config":"{\"type\":\"smart_open\",\"params\":{\"uri\":\"gs://cluster-anywhere/ray_job_spill\"}}"}'

  sudo tailscale funnel --bg --https 443 http://localhost:8265
  #sudo tailscale funnel --bg --tcp 8443 tcp://localhost:6379
  #sudo tailscale funnel --bg --tcp 5432 tcp://localhost:5432


# elif [ "$LOCATION" = "Vast" ]; then
#   node_master='-Cnode.master=false \\'
#   node_data='-Cnode.data=false \\'
#   node_voting_only='-Cnode.voting_only=false \\'
#   discovery_zen_minimum_master_nodes='-Cdiscovery.zen.minimum_master_nodes=3 \\'
#   echo "nameserver 100.100.100.100" | sudo tee /etc/resolv.conf
#   echo "search chimp-beta.ts.net" | sudo tee -a /etc/resolv.conf
#   # #There isn't a tun so we can't create a tunnel interface. So we've told cratedb to use eth0.
#   sudo sed -i "s/_tailscale0_/_eth0_/g" /crate/config/crate.yml
#   ray start --address='nexus.chimp-beta.ts.net:6379' --resources='{"'"$LOCATION"'": '$(nproc)'}' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $IPADDRESS --node-name $HOSTNAME.chimp-beta.ts.net #--object-store-memory=$ray_object_store


elif [ ! "$LOCATION" = "OnPrem" ] && [ ! "$NODETYPE" = "head" ]; then
  node_master='-Cnode.master=false \\'
  node_data='-Cnode.data=false \\'
  node_voting_only='-Cnode.voting_only=false \\'
  discovery_zen_minimum_master_nodes='-Cdiscovery.zen.minimum_master_nodes=3 \\'


  ray start --address='nexus.chimp-beta.ts.net:6379' --resources='{"'"$LOCATION"'": '$(nproc)'}' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net #--object-store-memory=$ray_object_store


elif [ "$NODETYPE" = "user" ]; then
  #these should be reenabled again once i have a few more cluster nodes 19/9/2025
  #node_master='-Cnode.master=false \\'
  #node_data='-Cnode.data=false \\'
  #node_voting_only='-Cnode.voting_only=false \\'
  discovery_zen_minimum_master_nodes='-Cdiscovery.zen.minimum_master_nodes=3 \\'

  #todo: https://docs.ray.io/en/latest/ray-core/using-ray-with-jupyter.html#setting-up-notebook

  #sudo tailscale funnel --bg https+insecure://localhost:8888
  #enabled crate locally so that OpenHands can access it easier. Assuming that opening the ports in the container and in tailscale doesn't exclude it from tailscale
  sudo tailscale funnel --bg --tcp 4200 tcp://localhost:4200
  #sudo tailscale funnel --bg --tcp 5432 tcp://localhost:5432

  ray start --address='nexus.chimp-beta.ts.net:6379' --num-cpus=1 --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net &

  if [ -e "/files" ]; then
    sudo chgrp -R crate /files
    sudo chmod -R 777 /files
  fi

  conda config --set default_threads $(nproc)
  conda config --set repodata_threads $(nproc)
  conda config --set fetch_threads $(nproc)
  conda config --set pip_interop_enabled true
  conda config --append channels rapidsai
  conda config --append channels conda-forge
  #using OpenHands instead of Jupyter Notebooks. So disabled all of the jupyter stuff
  #export JUPYTERLAB_SETTINGS_DIR='/data/.jupyter/lab/user-settings/'
  #export JUPYTERLAB_WORKSPACES_DIR='/data/.jupyter/lab/workspaces/'
  #conda install --strict-channel-priority -y ipympl 'ipywidgets>=8' jupyterlab 'cudf=24.12' libta-lib nodejs nano ta-lib
  #jupyter-lab --allow-root --IdentityProvider.token='' --ServerApp.password='' --notebook-dir /files --ip 0.0.0.0 --no-browser --certfile=/data/certs/${HOSTNAME,,}.chimp-beta.ts.net.crt --keyfile=/data/certs/${HOSTNAME,,}.chimp-beta.ts.net.key --preferred-dir /files &
  #look into using /lab or /admin or whatever so that they can live on the same port (on the head node perhaps)
  #but we can't move it to the head node right now because the only other port is 10001 and that conflicts with ray
  #eventually we can make the below lines available to all nodetypes for cluster health checks. but first we need to configured the instances to connect was a password when connecting remotely.
else

    # if [ ! "$LOCATION" = "OnPrem" ] && [ $ALL_PROXY ]; then
    #  ray start --address='nexus.chimp-beta.ts.net:6379' --resources='{"'"$LOCATION"'": '$(nproc)'}' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net
    #   #ssh -N -L localhost:6379:localhost:1055 $USER@localhost
    # else

    ray start --address='nexus.chimp-beta.ts.net:6379' --resources='{"'"$LOCATION"'": '$(nproc)'}' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net
    # fi
    echo "Done"
    sudo tailscale funnel --bg --https 443 https+insecure://localhost:8265

fi

# sudo sudo apt install -yq --no-install-recommends davfs2
sudo rm -f /var/run/mount.davfs/data-tailscale-drive.pid
sudo mkdir -pv /data/tailscale/drive
echo -e '\n\n' | sudo mount -t davfs http://100.100.100.100:8080/jcoffi.github/ /data/tailscale/drive -o uid=1000,gid=crate,suid,user=ray,username=ray




#this won't work with the load balancer. the port on the container needs to be opened.
#gonna make it available to all container instances
#sudo tailscale funnel --bg --yes --https 443 /tmp/health_status.html


# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
function term_handler(){
    davfs2_pid=$(pgrep -f davfs)
    crate_pid=$(pgrep -f crate)
    #if [ $(tailscale status -json | jq -r .BackendState | grep -q "Running") ]; then
    if [ $crate_pid ]; then
      echo "Running Cluster Decommission"
      /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &
    fi

    if [ $(ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q "ALIVE") ]; then
        echo "***Stopping Ray***"
        ray stop -g 20
    fi


    echo "tailscale logout"
    sudo tailscale logout
    sudo tailscale down
    sudo tailscaled -cleanup

    if [ $crate_pid ]; then
        sudo kill -TERM $crate_pid
    fi
    if [ $davfs2_pid ]; then
        sudo umount /data/tailscale/drive
        sudo kill -TERM $davfs2_pid
    else
        sudo rm -f /var/run/mount.davfs/data-tailscale-drive.pid
    fi
    #fi
    exit 0
}

function error_handler(){
    echo "***Error***"
    echo "***Stopping Ray***"
    ray stop -g 20
    #echo "Running Cluster Election"
    #/usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'new_primaries';" &
    echo "Running Decommission"
    /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &

    echo "tailscale logout"
    sudo tailscale logout
    sudo tailscale down
    sudo tailscaled -cleanup
    crate_pid=$(pgrep -f crate)
    davfs2_pid=$(pgrep -f davfs)
    sudo kill -TERM 1

    if [ $davfs2_pid ]; then
        sudo umount /data/tailscale/drive
        sudo kill -TERM $davfs2_pid
    else
        sudo rm -f /var/run/mount.davfs/data-tailscale-drive.pid
    fi

    if [ $crate_pid ]; then
        sudo kill -TERM $crate_pid
    fi

    exit 1
}

# Setup signal handlers
trap 'term_handler' SIGTERM
trap 'term_handler' SIGKILL
trap 'term_handler' EXIT
trap 'error_handler' ERR
trap 'error_handler' SIGSEGV

/crate/bin/crate \
            ${cluster_initial_master_nodes}
            ${discovery_zen_minimum_master_nodes}
            ${discovery_seed_hosts}
            ${node_name}
            ${node_master}
            ${node_data}
            ${node_voting_only}
            ${node_store_allow_mmap}


#/usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'all';" &
#CREATE REPOSITORY s3backup TYPE s3
#[ WITH (parameter_name [= value], [, ...]) ]
#[ WITH (access_key = ${AWS_ACCESS_KEY_ID}, secret_key = ${AWS_SECRET_ACCESS_KEY}), endpoint = s3.${AWS_DEFAULT_REGION}.amazonaws.com, bucket = ${AWS_S3_BUCKET}, base_path=crate/ ]
#



#while true
#do
#  tail -f /dev/null & wait ${!}
#done
