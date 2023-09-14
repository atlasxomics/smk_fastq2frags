from pathlib import Path

from latch.types.directory import LatchDir
from latch.types.file import LatchFile
from latch.types.metadata import LatchAuthor, SnakemakeFileParameter, SnakemakeMetadata

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
	    path=Path("fastqs/sample1/sample1_R1.fastq.gz")
        ),
        "r2": SnakemakeFileParameter(
	    type=LatchFile,
            display_name="read 2",
	    path=Path("fastqs/sample1/sample1_R2.fastq.gz")
        )
    }
)
