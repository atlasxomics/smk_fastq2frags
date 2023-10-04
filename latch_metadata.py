from pathlib import Path

from latch.types.file import LatchFile
from latch.types.metadata import (
    LatchAuthor, SnakemakeFileParameter, SnakemakeMetadata
)

SnakemakeMetadata(
    display_name="snaTAC",
    author=LatchAuthor(
        name="AtlasXomics, Inc.",
        email="jamesm@atlasxomics.com",
        github="github.com/jpmcga",
    ),
    parameters={
        "r1": SnakemakeFileParameter(
	        type=LatchFile,
            display_name="read 1",
            description="Read 1 fastq.gz file.",
	        path=Path("fastqs/sample1/sample1_R1.fastq.gz")
        ),
        "r2": SnakemakeFileParameter(
	        type=LatchFile,
            display_name="read 2",
            description="Read 2 fastq.gz file.",
	        path=Path("fastqs/sample1/sample1_R2.fastq.gz")
        ),
        "reference_genome_pointer": SnakemakeFileParameter(
            type=LatchFile,
            display_name="reference genome pointer",
            description="Test file containing remote path to a reference genome \
                directory, containing genome.fa and genome.index files",
            path=Path("reference.txt")
        ),
        "barcode_file": SnakemakeFileParameter(
            type=LatchFile,
            display_name="barcode file",
            description="File listing barcodes used in this experiment.",
            path=Path("barcodes.txt")
        )
    }
)
