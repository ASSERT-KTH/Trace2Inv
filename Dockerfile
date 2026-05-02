# syntax=docker/dockerfile:1
# ── Base: matches upstream python:3.10.12-slim-buster exactly ─────────────────
FROM python:3.10.12-slim-buster

# ── system deps ────────────────────────────────────────────────────────────────
# coreutils  – upstream requires timeout(1)
# git        – crytic-compile/slither resolves contract imports via git
# curl/wget  – solc-select downloads compiler binaries at runtime
# build-essential + libssl-dev + libffi-dev – native C wheels (cytoolz, etc.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        coreutils \
        git \
        curl \
        wget \
        build-essential \
        libssl-dev \
        libffi-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /Trace2Inv

# ── copy source (mirrors upstream: COPY . /Trace2Inv/) ────────────────────────
COPY . /Trace2Inv/

# ── Python deps + solc-select + Vyper (all consolidated into one RUN) ──────────
# solc versions: 0.5.17/0.5.18 – lending contracts; 0.8.4 – newer contracts
# Vyper 0.2.8 – BeanstalkFarms benchmark
RUN pip install --no-cache-dir --upgrade pip \
    && python3.10 -m pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir solc-select \
    && solc-select install 0.5.17 \
    && solc-select install 0.5.18 \
    && solc-select install 0.8.4 \
    && solc-select use 0.8.4 \
    && pip install --no-cache-dir "vyper==0.2.8"

# ── offline smoke test ─────────────────────────────────────────────────────────
# Verifies only the packages actually listed in requirements.txt are importable.
# web3 is not a direct dep – it arrives transitively via slither_analyzer.
# hadolint ignore=SC2015
RUN python3.10 -c "\
import sys, importlib.util; \
pkgs = ['eth_abi', 'hexbytes', 'networkx', 'numpy', 'packaging', \
        'requests', 'slither', 'tinyrpc', 'toml']; \
missing = [p for p in pkgs if importlib.util.find_spec(p) is None]; \
[print(f'  ok  {p}') for p in pkgs if p not in missing]; \
[print(f'  MISSING  {p}', file=sys.stderr) for p in missing]; \
sys.exit(1) if missing else print('Smoke test passed.')"

# ── runtime note ───────────────────────────────────────────────────────────────
# settings.toml holds secrets: EtherScanApiKeys, rpcProviders, ethArchives.
# Mount it at runtime – never bake it into the image:
#   docker run -v $(pwd)/settings.toml:/Trace2Inv/settings.toml:ro ...
# See settings.toml.template for the required structure.
#
# main.py reads pre-cached data/executionTable.pkl and data/accesslistTable.pkl.
# It accepts one positional argument: AC | TL | GC | RE | SS | OR | DF | MF
# Example: docker run ... python3.10 main.py AC

CMD ["python3.10", "-c", "print('Trace2Inv ready. Usage: python3.10 main.py [AC|TL|GC|RE|SS|OR|DF|MF]')"]

