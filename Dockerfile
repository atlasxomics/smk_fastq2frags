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

# install jdk, bbmap
RUN apt-get install -y default-jdk
RUN curl -L https://sourceforge.net/projects/bbmap/files/BBMap_39.01.tar.gz/download -o \
    BBMap_39.01.tar.gz && \
    tar -xvzf BBMap_39.01.tar.gz && \
    rm BBMap_39.01.tar.gz

# cellranger
RUN curl -o cellranger-atac-2.1.0.tar.gz "https://cf.10xgenomics.com/releases/cell-atac/cellranger-atac-2.1.0.tar.gz?Expires=1694756765&Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9jZi4xMHhnZW5vbWljcy5jb20vcmVsZWFzZXMvY2VsbC1hdGFjL2NlbGxyYW5nZXItYXRhYy0yLjEuMC50YXIuZ3oiLCJDb25kaXRpb24iOnsiRGF0ZUxlc3NUaGFuIjp7IkFXUzpFcG9jaFRpbWUiOjE2OTQ3NTY3NjV9fX1dfQ__&Signature=fDlvn4Af9oO~dgGAdza~U32SWQkqqz6ehCQjDPmsZcmVAWNo~YK1Jva7f6Kn8UzhDJfL6Mt4Kj8HAQS4gnZBhEaKhGvA0onrx8MElz-EAP6Rj0deM2dqzAyJ1DdNlpcg2AXjxiILCpnqB5YBxg2Qlqnu5-k4nIVN8U2Mf8FmXqSmCz5~mNP5reIg-J02ep4wdCWW5g3Gvx48Ao-cW15fCsdcn9ENf~DH8XQjRFL~PkzuzUECpXBRfbxHdW~PyC6UMKnz1tSrp0k~BahMKeW9rloWFGAHxPSYF4dtYHPKBlSxuGKxeQ5IExkKgtPTey~OgZ7x8-B6qZa0m3hq4CKq-Q__&Key-Pair-Id=APKAI7S6A5RYOXBWRPDA" && \ 
    tar -xzvf cellranger-atac-2.1.0.tar.gz && \
    rm cellranger-atac-2.1.0.tar.gz
COPY ./bc50.txt.gz /root/cellranger-atac-2.1.0/lib/python/atac/barcodes/737K-cratac-v1.txt.gz

# Copy workflow data (use .dockerignore to skip files)
copy . /root/
copy ./.latch/snakemake_jit_entrypoint.py /root/snakemake_jit_entrypoint.py

# Latch workflow registration metadata
# DO NOT CHANGE
arg tag
# DO NOT CHANGE
env FLYTE_INTERNAL_IMAGE $tag

workdir /root
