"""Snakemake pipeline for converting raw fastq data to ATAC-seq fragments
"""

from typing import List
import fnmatch
import os
import pdb

configfile: "config.yaml"

def get_samples(fastq_dir: str) -> List[str]:
  return [dir for dir in os.listdir(fastq_dir)]

def get_r1_path(fastq_dir: str, sample: str) -> str:
  r1 = fnmatch.filter(os.listdir(f'{fastq_dir}/{sample}'), f'*1*.fastq.gz')[0]
  return os.path.join(fastq_dir, sample, r1)

def get_r2_path(fastq_dir: str, sample: str) -> str:
  r2 = fnmatch.filter(os.listdir(f'{fastq_dir}/{sample}'), f'*2*.fastq.gz')[0]
  return os.path.join(fastq_dir, sample, r2)

sample = get_samples(config["fastq_dir"])[0]

rule all:
  input:
    expand('{sample}/outs', sample=get_samples(config["fastq_dir"]))

rule filter_L1:
  input:
    in1 = get_r1_path(config["fastq_dir"], sample),
    in2 = get_r2_path(config["fastq_dir"], sample)
  output:
    out1 = f'{sample}_linker1_R1.fastq.gz',
    out2 = f'{sample}_linker1_R2.fastq.gz'
  shell:
    '''
    bbmap/bbduk.sh \
    in1={input.in1} \
    in2={input.in2} \
    outm1={output.out1} \
    outm2={output.out2} \
    k=30 \
    mm=f \
    rcomp=f \
    restrictleft=103 \
    skipr1=t \
    hdist=3 \
    stats={sample}_stats.linker1.txt \
    threads=32 \
    literal=GTGGCCGATGTTTCGCATCGGCGTACGACT
    '''

rule filter_L2:
  input:
    in1 = f'{sample}_linker1_R1.fastq.gz',
    in2 = f'{sample}_linker1_R2.fastq.gz'
  output:
    out1 = f'{sample}_linker2_R1.fastq.gz',
    out2 = f'{sample}_linker2_R2.fastq.gz'
  shell:
    '''
    bbmap/bbduk.sh \
    in1={input.in1} \
    in2={input.in2} \
    outm1={output.out1} \
    outm2={output.out2} \
    k=30 \
    mm=f \
    rcomp=f \
    restrictleft=65 \
    skipr1=t \
    hdist=3 \
    stats={sample}_stats.linker2.txt \
    threads=32 \
    literal=ATCCACGTGCTTGAGAGGCCAGAGCATTCG
    '''

rule split_r2:
  input:
    f'{sample}_linker2_R2.fastq.gz'
  output:
    out1 = f'{sample}_S1_L001_R3_001.fastq',
    out2 = f'{sample}_S1_L001_R2_001.fastq'
  shell:
    '''
    python split_r2.py \
    --input {input} \
    --output_R3 {output.out1} \
    --output_R2 {output.out2}
    '''

rule R1_rename: 
  input:
    f'{sample}_linker2_R1.fastq.gz'
  output:
    f'{sample}_S1_L001_R1_001.fastq.gz'
  shell:
    '''
    cp {input} {output}
    '''

rule cell_ranger:
  input:
    in1 = f'{sample}_S1_L001_R1_001.fastq.gz',
    in2 = f'{sample}_S1_L001_R2_001.fastq',
    in3 = f'{sample}_S1_L001_R3_001.fastq'
  output:
    directory(f'{sample}/outs')
  params:
    ref_dir = config["ref_dir"]
  run:
    if not os.path.exists("cr_inputs"):
      os.makedir("cr_inputs")
    shell('mv {input.in1} {input.in2} {input.in3} cr_inputs')
    shell(
    "cellranger-atac-2.1.0/cellranger-atac count \
    --id={sample} \
    --reference={params.ref_dir} \
    --fastqs=cr_inputs \
    --sample={sample} \
    --localcores=25 \
    --localmem=64 \
    --force-cells=2500"
    )
