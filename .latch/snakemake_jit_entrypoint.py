import json
import os
import subprocess
import tempfile
import textwrap
import time
import sys
from functools import partial
from pathlib import Path
import shutil
from typing import List, NamedTuple, Optional, TypedDict
import hashlib
from urllib.parse import urljoin

import stat
import base64
import boto3
import boto3.session
import google.protobuf.json_format as gpjson
import gql
import requests
from flytekit.core import utils
from flytekit.extras.persistence import LatchPersistence
from latch_cli import tinyrequests
from latch_cli.centromere.utils import _construct_dkr_client
from latch_sdk_config.latch import config
from latch_cli.services.register.register import (
    _print_reg_resp,
    _recursive_list,
    register_serialized_pkg,
    print_and_write_build_logs,
    print_upload_logs,
)
from latch_cli.snakemake.serialize import (
    extract_snakemake_workflow,
    generate_snakemake_entrypoint,
    serialize_snakemake,
)
import latch_cli.snakemake

from latch import small_task
from latch_sdk_gql.execute import execute
from latch.types.directory import LatchDir
from latch.types.file import LatchFile

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

def check_exists_and_rename(old: Path, new: Path):
    if new.exists():
        print(f"A file already exists at {new} and will be overwritten.")
        if new.is_dir():
            shutil.rmtree(new)
    os.renames(old, new)

def si_unit(num, base: float = 1000.0):
    for unit in (" ", "k", "M", "G", "T", "P", "E", "Z"):
        if abs(num) < base:
            return f"{num:3.1f}{unit}"
        num /= base
    return f"{num:.1f}Y"

def file_name_and_size(x: Path):
    s = x.stat()

    if stat.S_ISDIR(s.st_mode):
        return f"{'D':>8} {x.name}/"

    return f"{si_unit(s.st_size):>7}B {x.name}"

@small_task
def snakemake_snatac_jit_register_task(
    r1: LatchFile,
    r2: LatchFile
) -> bool:
    r1_dst_p = Path("fastqs/sample1/sample1_R1.fastq.gz")

    print(f"Downloading r1: {r1.remote_path}")
    r1_p = Path(r1).resolve()
    print(f"  {file_name_and_size(r1_p)}")

    print(f"Moving r1 to {r1_dst_p}")
    check_exists_and_rename(
        r1_p,
        r1_dst_p
    )

    r2_dst_p = Path("fastqs/sample1/sample1_R2.fastq.gz")

    print(f"Downloading r2: {r2.remote_path}")
    r2_p = Path(r2).resolve()
    print(f"  {file_name_and_size(r2_p)}")

    print(f"Moving r2 to {r2_dst_p}")
    check_exists_and_rename(
        r2_p,
        r2_dst_p
    )

    image_name = "13502_snakemake_snatac:0.0.15-3dfa38"
    image_base_name = image_name.split(":")[0]
    account_id = "13502"
    snakefile = Path("Snakefile")

    lp = LatchPersistence()
    pkg_root = Path(".")

    exec_id_hash = hashlib.sha1()
    exec_id_hash.update(os.environ["FLYTE_INTERNAL_EXECUTION_ID"].encode("utf-8"))
    version = exec_id_hash.hexdigest()[:16]

    wf = extract_snakemake_workflow(pkg_root, snakefile, version)
    wf_name = wf.name
    generate_snakemake_entrypoint(wf, pkg_root, snakefile, None)

    entrypoint_remote = f"latch:///.snakemake_latch/workflows/{wf_name}/entrypoint.py"
    lp.upload("latch_entrypoint.py", entrypoint_remote)
    print(f"latch_entrypoint.py -> {entrypoint_remote}")
    dockerfile = Path("Dockerfile-dynamic").resolve()
    dockerfile.write_text(
    textwrap.dedent(
            f'''
            from 812206152185.dkr.ecr.us-west-2.amazonaws.com/{image_name}

            copy latch_entrypoint.py /root/latch_entrypoint.py
            '''
        )
    )
    new_image_name = f"{image_name}-{version}"

    os.mkdir("/root/.ssh")
    ssh_key_path = Path("/root/.ssh/id_rsa")
    cmd = ["ssh-keygen", "-f", ssh_key_path, "-N", "", "-q"]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        raise ValueError(
            "There was a problem creating temporary SSH credentials. Please ensure"
            " that `ssh-keygen` is installed and available in your PATH."
        ) from e
    os.chmod(ssh_key_path, 0o700)

    token = os.environ.get("FLYTE_INTERNAL_EXECUTION_ID", "")
    headers = {
        "Authorization": f"Latch-Execution-Token {token}",
    }

    ssh_public_key_path = Path("/root/.ssh/id_rsa.pub")
    response = tinyrequests.post(
        config.api.centromere.provision,
        headers=headers,
        json={
            "public_key": ssh_public_key_path.read_text().strip(),
        },
    )

    resp = response.json()
    try:
        public_ip = resp["ip"]
        username = resp["username"]
    except KeyError as e:
        raise ValueError(
            f"Malformed response from request for centromere login: {resp}"
        ) from e


    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"{username}@{public_ip}", "uptime"])
    dkr_client = _construct_dkr_client(ssh_host=f"ssh://{username}@{public_ip}")

    data = {"pkg_name": new_image_name.split(":")[0], "ws_account_id": account_id}
    response = requests.post(config.api.workflow.upload_image, headers=headers, json=data)

    try:
        response = response.json()
        access_key = response["tmp_access_key"]
        secret_key = response["tmp_secret_key"]
        session_token = response["tmp_session_token"]
    except KeyError as err:
        raise ValueError(f"malformed response on image upload: {response}") from err

    try:
        client = boto3.session.Session(
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            aws_session_token=session_token,
            region_name="us-west-2",
        ).client("ecr")
        token = client.get_authorization_token()["authorizationData"][0][
            "authorizationToken"
        ]
    except Exception as err:
        raise ValueError(
            f"unable to retreive an ecr login token for user {account_id}"
        ) from err

    user, password = base64.b64decode(token).decode("utf-8").split(":")
    dkr_client.login(
        username=user,
        password=password,
        registry=config.dkr_repo,
    )

    image_build_logs = dkr_client.build(
        path=str(pkg_root),
        dockerfile=str(dockerfile),
        buildargs={"tag": f"{config.dkr_repo}/{new_image_name}"},
        tag=f"{config.dkr_repo}/{new_image_name}",
        decode=True,
    )
    print_and_write_build_logs(image_build_logs, new_image_name, pkg_root)

    upload_image_logs = dkr_client.push(
        repository=f"{config.dkr_repo}/{new_image_name}",
        stream=True,
        decode=True,
    )
    print_upload_logs(upload_image_logs, new_image_name)

    temp_dir = tempfile.TemporaryDirectory()
    with Path(temp_dir.name).resolve() as td:
        serialize_snakemake(wf, td, new_image_name, config.dkr_repo)

        protos = _recursive_list(td)
        reg_resp = register_serialized_pkg(protos, None, version, account_id)
        _print_reg_resp(reg_resp, new_image_name)

    wf_spec_remote = f"latch:///.snakemake_latch/workflows/{wf_name}/spec"
    spec_dir = Path("spec")
    for x_dir in spec_dir.iterdir():
        if not x_dir.is_dir():
            dst = f"{wf_spec_remote}/{x_dir.name}"
            print(f"{x_dir} -> {dst}")
            lp.upload(str(x_dir), dst)
            print("  done")
            continue

        for x in x_dir.iterdir():
            dst = f"{wf_spec_remote}/{x_dir.name}/{x.name}"
            print(f"{x} -> {dst}")
            lp.upload(str(x), dst)
            print("  done")

    class _WorkflowInfoNode(TypedDict):
        id: str


    nodes: Optional[List[_WorkflowInfoNode]] = None
    while not nodes:
        time.sleep(1)
        nodes = execute(
            gql.gql('''
            query workflowQuery($name: String, $ownerId: BigInt, $version: String) {
            workflowInfos(condition: { name: $name, ownerId: $ownerId, version: $version}) {
                nodes {
                    id
                }
            }
            }
            '''),
            {"name": wf_name, "version": version, "ownerId": account_id},
        )["workflowInfos"]["nodes"]

    if len(nodes) > 1:
        raise ValueError(
            "Invariant violated - more than one workflow identified for unique combination"
            " of {wf_name}, {version}, {account_id}"
        )

    print(nodes)

    for file in wf.return_files:
        print(f"Uploading {file.local_path} -> {file.remote_path}")
        lp.upload(file.local_path, file.remote_path)

    wf_id = nodes[0]["id"]
    params = gpjson.MessageToDict(wf.literal_map.to_flyte_idl()).get("literals", {})

    _interface_request = {
        "workflow_id": wf_id,
        "params": params,
    }

    response = requests.post(urljoin(config.nucleus_url, "/api/create-execution"), headers=headers, json=_interface_request)
    print(response.json())
    return True

