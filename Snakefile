"""Snakemake pipeline for converting raw fastq data to ATAC-seq fragments
"""

import fnmatch
import os

configfile: "config.yaml"

ref_dir = config["ref_dir"] 
cores_cellRanger = config["cores"]                              
mem = config["mem"]                       
fastq_dir = config["fastq_dir"]                                    
fastq_ext = config["fastq_ext"]                          
out_dir = config["out_dir"]                          
bbduk_path = config["bbduk_path"]                            
cellranger_path = config["cellranger_path"]

samples = [dir for dir in os.listdir(fastq_dir) if not dir.startswith('.')]
output = [f'{out_dir}/{sample}/complete.txt' for sample in samples]

fastq_paths={}
for sample in samples:

    # Make dict of fastq files {sample : (r1, r2)}
    fastq_paths[sample] = (
      fnmatch.filter(os.listdir(f'{fastq_dir}/{sample}'), f'*1*{fastq_ext}')[0],
      fnmatch.filter(os.listdir(f'{fastq_dir}/{sample}'), f'*2*{fastq_ext}')[0]
    )

    # Make output directories
    working_dir = f'{out_dir}/{sample}'
    filtered_dir = f'{working_dir}/filtered'
    cr_inputs = f'{working_dir}/cellranger_inputs' 

    (os.makedirs(dir) for dir in [working_dir, filtered_dir, cr_inputs]
     if not os.path.exists(dir))
            
rule all:
  input:
    output

rule filter_L1:
  input:
    in1 = lambda wildcards: f'{fastq_dir}/{sample}/{fastq_paths[wildcards.sample][0]}',
    in2 = lambda wildcards: f'{fastq_dir}/{sample}/{fastq_paths[wildcards.sample][1]}'
  output:
    out1 = f'{filtered_dir}/{sample}_linker1_R1.fastq.gz',
    out2 = f'{filtered_dir}/{sample}_linker1_R2.fastq.gz'
  shell:
    '''
    {bbduk_path} \
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
    stats={filtered_dir}/{sample}_stats.linker1.txt \
    threads={cores} \
    literal=GTGGCCGATGTTTCGCATCGGCGTACGACT
    '''

rule filter_L2:
  input:
    in1 = f'{filtered_dir}/{sample}_linker1_R1.fastq.gz',
    in2 = f'{filtered_dir}/{sample}_linker1_R2.fastq.gz'
  output:
    out1 = f'{filtered_dir}/{sample}_linker2_R1.fastq.gz',
    out2 = f'{filtered_dir}/{sample}_linker2_R2.fastq.gz'
  shell:
    '''
    {bbduk_path} \
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
    stats={filtered_dir}/{wildcards.sample}_stats.linker2.txt \
    threads={cores} \
    literal=ATCCACGTGCTTGAGAGGCCAGAGCATTCG
    '''

rule split_r2:
  input:
    f'{filtered_dir}/{sample}_linker2_R2.fastq.gz'
  output:
    out1 = f'{cr_inputs}/{sample}_S1_L001_R3_001.fastq',
    out2 = f'{cr_inputs}/{sample}_S1_L001_R2_001.fastq'
  shell:
    '''
    python split_r2.py \
    --input {input} \
    --output_R3 {output.out1} \
    --output_R2 {output.out2}
    '''

rule R1_rename: 
  input:
    f'{filtered_dir}/{sample}_linker2_R1.fastq.gz'
  output:
    f'{cr_inputs}/{sample}_S1_L001_R1_001.fastq.gz'
  shell:
    '''
    cp {input} {output}
    '''

rule cell_ranger:
  input:
    in1 = f'{cr_inputs}/{sample}_S1_L001_R1_001.fastq.gz',
    in2 = f'{cr_inputs}/{sample}_S1_L001_R2_001.fastq',
    in3 = f'{cr_inputs}/{sample}_S1_L001_R3_001.fastq'
  output:
    f'{working_dir}/complete.txt'
  shell:
    '''
    {cellranger_path} count \
    --id={sample} \
    --reference={ref_dir} \
    --fastqs={cr_inputs} \
    --sample={sample} \
    --localcores={cores_cellRanger} \
    --localmem={mem} \
    --force-cells=2500
    mv {sample} {working_dir}/cellranger_outputs
    touch {output}
    '''
