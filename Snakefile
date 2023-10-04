'''Snakemake pipeline for converting raw fastq data to ATAC-seq fragments
'''

import os
import re

with open("reference.txt") as f:
  REF_PATH =  f.readline().rstrip()

try:
  GENOME = re.search("GRC.*[0-9]{2}", REF_PATH).group()
except AttributeError:
  raise Exception("Genome name (GRC..XX) not found in pointer file.")

rule all:
  input:
    expand('{sample}_fragments.tsv.gz', sample=os.listdir('fastqs'))

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

rule chromap:
  input:
    in1 = '{sample}_linker2_R1.fastq.gz',
    in2 = '{sample}_linker2_R2.fastq.gz'
  output:
    '{sample}_aln.bed'
  threads: 96
  resources:
    mem_mb=192000,
    disk_mb=50000
  params:
    ref_path = REF_PATH,
    genome = GENOME
  run:
    shell(
      f'latch cp \
      {params.ref_path} \
      ./refdata'
    )
    shell(
      'chromap/chromap \
        -t 96 \
        --preset atac \
        -x refdata/{params.genome}_genome.index \
        -r refdata/{params.genome}_genome.fa \
        -1 {input.in1} \
        -2 {input.in2} \
        -o {wildcards.sample}_aln.bed \
        -b {input.in2} \
        --barcode-whitelist barcodes.txt \
        --read-format bc:22:29,bc:60:67,r1:0:-1,r2:117:-1'
    )

rule bed2fragment:
  input:
    '{sample}_aln.bed'
  output:
    '{sample}_fragments.tsv.gz'
  shell:
    '''	
    awk 'BEGIN{{FS=OFS=" "}}{{$4=$4"-1"}}4' {input} > {wildcards.sample}_temp.bed
    sed 's/ /\t/g' {wildcards.sample}_temp.bed > {wildcards.sample}_fragments.tsv
    bgzip -c {wildcards.sample}_fragments.tsv > {output}
    '''