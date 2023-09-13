from pathlib import Path

from latch.types.directory import LatchDir
from latch.types.file import LatchFile
from latch.types.metadata import LatchAuthor, SnakemakeFileParameter, SnakemakeMetadata

SnakemakeMetadata(
    display_name="snaTAC",
    author=LatchAuthor(
        name="AtlasXomics, Inc.",
        email="jamesm@atlasxomics.com",
        github="github.com/atlasxomics",
    ),
    parameters={
        "r1": SnakemakeFileParameter(
	    type=LatchFile,
            display_name="read 1",
	    path=Path("fastqs/sample1/sample1_R1_001.fastq.gz")
        ),
        "r2": SnakemakeFileParameter(
	    type=LatchFile,
            display_name="read 2",
	    path=Path("fastqs/sample1/sample1_R2_001.fastq.gz")
        ),
        "species": SnakemakeFileParameter(
	    type=LatchDir,
        display_name="species",
	    path=Path("refdata-cellranger-arc-GRCh38-2020-A-2.0.0")
        )
    }
)



