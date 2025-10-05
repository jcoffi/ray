ARG IMAGETYPE=cpu
ARG TS_AUTHKEY
ARG TSAPIKEY
FROM rayproject/ray:latest-py312-$IMAGETYPE
ENV __MODIN_AUTOIMPORT_PANDAS__=1 \
        MODIN_ENGINE=ray \
        MODIN_RAY_CLUSTER=True \
        RAY_IGNORE_UNHANDLED_ERRORS=1 \
        RAY_ADDRESS="nexus.chimp-beta.ts.net:6379" \
        RAY_CLIENT_RECONNECT_GRACE_PERIOD=60 \
        RAY_memory_monitor_refresh_ms=0 \
        RAY_record_ref_creation_sites=1 \
        TZ=America/Los_Angeles \
        NODETYPE=edge \
        AWS_DEFAULT_REGION="us-west-2" \
        AWS_S3_BUCKET="cluster-anywhere" \
        CRATE_GC_LOG_DIR="/data/crate/log" \
        CRATE_HEAP_DUMP_PATH="/data/crate/data" \
        CRATE_JAVA_OPTS="-XX:+IgnoreUnrecognizedVMOptions -XX:+UseContainerSupport -XX:+IdleTuningCompactOnIdle -XX:+IdleTuningGcOnIdle -Des.cgroups.hierarchy.override=/ -XX:+UseStringDeduplication $CRATE_JAVA_OPTS" \
        PATH=/crate/bin/:$PATH \
        CRATE_HEAP_SIZE="10G" \
        CRATE_HOME=/crate/bin/ \
        SQLALCHEMY_SILENCE_UBER_WARNING=1 \
        HOME=/home/ray \
        TS_STATEDIR="/data/tailscale" \
        TS_ACCEPT_DNS=true \
        TS_AUTHKEY=$TS_AUTHKEY \
        DEBIAN_FRONTEND=noninteractive \
        IPv6=false \
        DISABLE_IPV6=true


ARG OPENAPI_KEY
#        TSAPIKEY="" \
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
#        IPv6=false \
#        DISABLE_IPV6=true \

#we'll make the cluster name the github commit id, this way every new image is a new cluster but we keep state

VOLUME /data

RUN --mount=type=cache,target=/var/cache/apt sudo apt update \
&& sudo apt install -yq --no-install-recommends ca-certificates curl bc jq lsb-release \
&& curl -fsSLZ https://pkgs.tailscale.com/stable/ubuntu/focal.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
&& curl -fsSLZ https://pkgs.tailscale.com/stable/ubuntu/focal.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list \
&& sudo apt update \
&& sudo apt install -yq --no-install-recommends iptables nftables tailscale iproute2 procps inotify-tools debconf-utils libarchive-dev \
&& echo "davfs2 davfs2/suid_file boolean true" | sudo debconf-set-selections | sudo apt install -yq --no-install-recommends davfs2 \
&& sudo mkdir -p $CRATE_HEAP_DUMP_PATH $CRATE_GC_LOG_DIR $TS_STATEDIR \
&& sudo mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale \
&& sudo apt clean \
&& sudo groupadd crate \
&& export PLATFORM="$( case $(uname --m) in x86_64) echo x64_linux ;; aarch64) echo aarch64_linux ;; esac)" \
&& CRATE_LATEST_TAG=$(curl -fsSLZ https://api.github.com/repos/crate/crate/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') \
&& CRASH_LATEST_TAG=$(curl -fsSLZ https://api.github.com/repos/crate/crash/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') \
&& sudo mkdir -p /crate \
&& sudo adduser ray crate \
&& sudo chgrp -R crate /crate \
&& sudo chmod -R 774 /crate \
&& sudo chgrp -R crate /data \
&& sudo chmod -R 774 /data \
&& export CRATE_URL=https://cdn2.crate.io/downloads/releases/cratedb/${PLATFORM}/crate-${CRATE_LATEST_TAG}.tar.gz \
&& curl -fsSLZ -O ${CRATE_URL} \
&& curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/docker-crate/master/config/crate.yml" \
&& curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/docker-crate/master/config/log4j2.properties" \
&& sudo tar -xf crate-${CRATE_LATEST_TAG}.tar.gz -C /crate --strip-components=1 \
&& sudo chown 1000 crate.yml \
&& sudo chgrp crate crate.yml \
&& sudo mv crate.yml /crate/config/crate.yml \
&& sudo chown 1000 log4j2.properties \
&& sudo chgrp crate log4j2.properties \
&& sudo mv log4j2.properties /crate/config/log4j2.properties \
&& rm crate-${CRATE_LATEST_TAG}.tar.gz \
&& curl -fsSLZ -O https://cdn2.crate.io/downloads/releases/crash_standalone_latest \
&& sudo mv crash_standalone_latest /usr/local/bin/crash \
&& sudo chmod +x /usr/local/bin/crash \
&& $HOME/anaconda3/bin/pip install --no-cache-dir -U pip \
        cupy-cuda12x \
        pyarrow-hotfix \
        'pandas[performance]' \
        pandas_market_calendars \
        modin[ray] \
        sqlalchemy-cratedb \
        'dask[distributed]' \
        sympy \
        'scipy>=1.13' \
        scikit-learn \
        statsmodels \
        datetime \
        geojson \
        fredapi \
        'alpaca_py>=0.20.02' \
        tiingo \
        eodhd \
        openai \
        google-api-python-client \
        gcsfs \
        google-cloud-storage \
        smart_open \
        'ipywidgets>=8'\
        boto3

# Need to hold back numpy due to scipy version constraint

##building juicefs
#RUN JFS_LATEST_TAG=$(curl -s https://api.github.com/repos/juicedata/juicefs/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') && \
#  wget "https://github.com/juicedata/juicefs/releases/download/v${JFS_LATEST_TAG}/juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" && \
#  tar -zxf "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" && \
#  sudo install juicefs /usr/bin && \
#  rm juicefs "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz"

#for direct connections from tailscale
EXPOSE 41641/udp
#for external healthchecks
EXPOSE 80/tcp

ENTRYPOINT [ "/bin/bash", "-c", "curl -o /tmp/startup.sh https://raw.githubusercontent.com/jcoffi/ray/cluster-anywhere/docker/anywhere-tailscale/startup.sh && chmod +x /tmp/startup.sh && /tmp/startup.sh" ]
HEALTHCHECK --interval=60s --timeout=59s --start-period=300s --retries=4 \
CMD sh /home/ray/run_tests.sh
