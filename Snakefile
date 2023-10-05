'''Snakemake pipeline for converting raw fastq data to ATAC-seq fragments
'''

import os
import re


rule all:
  input:
    expand('{sample}_fragments.tsv.gz', sample=os.listdir('fastqs'))

rule filter_L1:
  input:
    in1='fastqs/{sample}/{sample}_R1.fastq.gz',
    in2='fastqs/{sample}/{sample}_R2.fastq.gz'
  output:
    out1='{sample}_linker1_R1.fastq.gz',
    out2='{sample}_linker1_R2.fastq.gz'
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
    in1='{sample}_linker1_R1.fastq.gz',
    in2='{sample}_linker1_R2.fastq.gz'
  output:
    out1='{sample}_linker2_R1.fastq.gz',
    out2='{sample}_linker2_R2.fastq.gz'
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
    in1='{sample}_linker2_R1.fastq.gz',
    in2='{sample}_linker2_R2.fastq.gz',
    in3='reference.txt',
    in4='barcodes.txt'
  output:
    '{sample}_aln.bed'
  threads: 32
  resources:
    mem_mb=128000,
    disk_mb=2000000
  run:
    with open('reference.txt') as f:
      ref_path = f.readline().rstrip()
    try:
      genome = re.search('GRC.*[0-9]{2}', ref_path).group()
    except AttributeError:
      raise Exception('Genome name (GRC..XX) not found in pointer file.')
    shell(f'latch cp {ref_path} ./refdata')
    shell(
      'chromap/chromap \
        -t 32 \
        --preset atac \
        -x refdata/{genome}_genome.index \
        -r refdata/{genome}_genome.fa \
        -1 {input.in1} \
        -2 {input.in2} \
        -o {wildcards.sample}_aln.bed \
        -b {input.in2} \
        --barcode-whitelist {input.in4} \
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