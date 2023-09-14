'''Snakemake pipeline for converting raw fastq data to ATAC-seq fragments
'''

import os

REF_DIR = 'refdata'

rule all:
  input:
    expand('{sample}/outs', sample=os.listdir('fastqs'))

rule filter_L1:
  input:
    in1 = 'fastqs/{sample}/{sample}_R1.fastq.gz',
    in2 = 'fastqs/{sample}/{sample}_R2.fastq.gz'
  output:
    out1 = '{sample}_linker1_R1.fastq.gz',
    out2 = '{sample}_linker1_R2.fastq.gz'
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
    stats=filter_stats.linker1.txt \
    threads=32 \
    literal=GTGGCCGATGTTTCGCATCGGCGTACGACT
    '''

rule filter_L2:
  input:
    in1 = '{sample}_linker1_R1.fastq.gz',
    in2 = '{sample}_linker1_R2.fastq.gz'
  output:
    out1 = '{sample}_linker2_R1.fastq.gz',
    out2 = '{sample}_linker2_R2.fastq.gz'
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
    stats=filter_stats.linker2.txt \
    threads=32 \
    literal=ATCCACGTGCTTGAGAGGCCAGAGCATTCG
    '''

rule split_r2:
  input:
    input = '{sample}_linker2_R2.fastq.gz'
  output:
    out1 = '{sample}_S1_L001_R3_001.fastq',
    out2 = '{sample}_S1_L001_R2_001.fastq'
  shell:
    '''
    python split_r2.py \
    --input {input} \
    --output_R3 {output.out1} \
    --output_R2 {output.out2}
    '''

rule R1_rename: 
  input:
    input = '{sample}_linker2_R1.fastq.gz'
  output:
    output = '{sample}_S1_L001_R1_001.fastq.gz'
  shell:
    '''
    cp {input} {output}
    '''

rule cell_ranger:
  input:
    in1 = '{sample}_S1_L001_R1_001.fastq.gz',
    in2 = '{sample}_S1_L001_R2_001.fastq',
    in3 = '{sample}_S1_L001_R3_001.fastq'
  output:
    directory('{sample}/outs')
  params:
    ref_dir = REF_DIR
  run:
    if not os.path.exists('cr_inputs'):
      os.mkdir('cr_inputs')
    shell('mv {input.in1} {input.in2} {input.in3} cr_inputs')
    shell(
    'cellranger-atac-2.1.0/cellranger-atac count \
    --id={wildcards.sample} \
    --reference={params.ref_dir} \
    --fastqs=cr_inputs \
    --sample={wildcards.sample} \
    --localcores=25 \
    --localmem=64 \
    --force-cells=2500'
    )
