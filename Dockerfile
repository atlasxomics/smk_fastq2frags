# DO NOT CHANGE
from 812206152185.dkr.ecr.us-west-2.amazonaws.com/latch-base:fe0b-main

workdir /tmp/docker-build/work/

shell [ \
    "/usr/bin/env", "bash", \
    "-o", "errexit", \
    "-o", "pipefail", \
    "-o", "nounset", \
    "-o", "verbose", \
    "-o", "errtrace", \
    "-O", "inherit_errexit", \
    "-O", "shift_verbose", \
    "-c" \
]
env TZ='Etc/UTC'
env LANG='en_US.UTF-8'

arg DEBIAN_FRONTEND=noninteractive

# Latch SDK
# DO NOT REMOVE
run pip install latch==2.32.6
run mkdir /opt/latch

# Install Mambaforge
run apt-get update --yes && \
    apt-get install --yes curl && \
    curl \
        --location \
        --fail \
        --remote-name \
        https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh && \
    `# Docs for -b and -p flags: https://docs.anaconda.com/anaconda/install/silent-mode/#linux-macos` \
    bash Mambaforge-Linux-x86_64.sh -b -p /opt/conda -u && \
    rm Mambaforge-Linux-x86_64.sh

# Set conda PATH
env PATH=/opt/conda/bin:$PATH

# Build conda environment
copy environment.yaml /opt/latch/environment.yaml
run mamba env create \
    --file /opt/latch/environment.yaml \
    --name snakemake
env PATH=/opt/conda/envs/snakemake/bin:$PATH

# install jdk fo bbmap
RUN apt-get install -y default-jdk

# Copy workflow data (use .dockerignore to skip files)
copy . /root/
copy ./.latch/snakemake_jit_entrypoint.py /root/snakemake_jit_entrypoint.py

# Latch workflow registration metadata
# DO NOT CHANGE
arg tag
# DO NOT CHANGE
env FLYTE_INTERNAL_IMAGE $tag

workdir /root
