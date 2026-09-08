# =============================================================================
# SharkVNTyper — docker image: shark + VNtyper (k-mer / Kestrel mode)
#
# Contents:
#   - shark (built from ./shark, bundled sdsl-lite)                   -> /usr/local/bin/shark
#   - vntyper.py (modified VNtyper 1.3.0) + Files/ (MUC1-VNTR.fa, motifs) -> /opt/sharkvntyper/vntyper/
#   - Kestrel 1.0.1 (path HARD-CODED in vntyper.py, kmer_command_k20)
#                                                                      -> /usr/local/lib/kestrel-1.0.1/kestrel.jar
#   - fastp, java (JRE), python3 + pandas/numpy/regex/biopython/pysam
#   - sharkvntyper.sh                                                  -> /usr/local/bin/sharkvntyper
#   - ref/muc1_seqs.fasta (shark reference, built by the team)         -> /opt/sharkvntyper/ref/
#
# Deliberately not included (--ignore_advntr mode only):
#   code-adVNTR, bwa, picard, sambamba, chr1.fa (only used by the BAM /
#   adVNTR branches of VNtyper).
#
# Build:  docker build -t sharkvntyper:1.2.0 .
# Run  :  docker run --rm -v /data:/data sharkvntyper:1.2.0 \
#             -1 /data/S_R1.fastq.gz -2 /data/S_R2.fastq.gz -o /data/out
# NB: Kestrel is started with -Xmx15g (vntyper.py) -> give the container
#     at least 16 GB of memory.
# =============================================================================

# ---------- stage 1: build shark ---------------------------------------------
FROM ubuntu:24.04 AS shark-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake zlib1g-dev git \
    && rm -rf /var/lib/apt/lists/*
COPY shark /build/shark
WORKDIR /build/shark
# sdsl-lite (v2.1.1, bundled): install.sh <prefix> installs include/ and lib/
# into the shark directory, as expected by the Makefile (-I./include -L./lib)
RUN cd sdsl-lite && ./install.sh /build/shark && cd .. && make \
    && ./shark -r example/ENSG00000277117.fa -1 example/sample_1.fq -2 example/sample_2.fq \
         -o /tmp/s1.fq -p /tmp/s2.fq > /tmp/s.ssv \
    && cmp /tmp/s1.fq example/sharked.sample_1.truth.fq \
    && cmp /tmp/s2.fq example/sharked.sample_2.truth.fq

# ---------- stage 2: final image ---------------------------------------------
# ubuntu:24.04 (not 22.04): VNtyper runs fastp with --dedup / --dup_calc_accuracy,
# available since fastp 0.22.0; the 22.04 package is 0.20.1, the 24.04 one is 0.23.4.
FROM ubuntu:24.04
LABEL org.opencontainers.image.title="SharkVNTyper" \
      org.opencontainers.image.description="shark read filtering + VNtyper (Kestrel) MUC1-VNTR genotyping" \
      org.opencontainers.image.version="1.2.0" \
      org.opencontainers.image.licenses="BSD-3-Clause AND GPL-3.0-only AND LGPL-3.0-only"
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
ARG KESTREL_VERSION=1.0.1
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip \
        openjdk-17-jre-headless \
        fastp \
        zlib1g libgomp1 \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    # fastp must support --dedup (>= 0.22.0)
    && fastp --help 2>&1 | grep -q -- '--dedup' \
    # Kestrel: path imposed by vntyper.py (/usr/local/lib/kestrel-1.0.1/kestrel.jar)
    && curl -fsSL -o /tmp/kestrel.tar.gz \
         https://github.com/paudano/kestrel/releases/download/${KESTREL_VERSION}/kestrel-${KESTREL_VERSION}-linux.tar.gz \
    # the archive directly contains kestrel-<version>/ (kestrel.jar + slf4j, commons-lang3, getopt jars, licenses)
    && tar -xzf /tmp/kestrel.tar.gz -C /usr/local/lib \
    && rm -f /tmp/kestrel.tar.gz \
    && test -f /usr/local/lib/kestrel-${KESTREL_VERSION}/kestrel.jar

# Python dependencies listed in the VNtyper README (pandas, numpy, regex, biopython, pysam)
COPY requirements.txt /tmp/requirements.txt
# --break-system-packages: PEP 668 (Ubuntu 24.04 system python), no venv needed in a container
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt && rm /tmp/requirements.txt

COPY --from=shark-builder /build/shark/shark /usr/local/bin/shark
COPY vntyper /opt/sharkvntyper/vntyper
COPY ref     /opt/sharkvntyper/ref
COPY LICENSE THIRD_PARTY_LICENSES.md /opt/sharkvntyper/
COPY shark/LICENSE /opt/sharkvntyper/LICENSE.shark
COPY sharkvntyper.sh /usr/local/bin/sharkvntyper
RUN chmod +x /usr/local/bin/sharkvntyper /usr/local/bin/shark

ENV SHARKVNTYPER_VNTYPER_PY=/opt/sharkvntyper/vntyper/vntyper.py \
    SHARKVNTYPER_VNTYPER_DIR=/opt/sharkvntyper/vntyper/ \
    SHARKVNTYPER_SHARK_REF=/opt/sharkvntyper/ref/muc1_seqs.fasta \
    SHARKVNTYPER_REF_VNTR=/opt/sharkvntyper/vntyper/Files/MUC1-VNTR.fa

WORKDIR /data
ENTRYPOINT ["sharkvntyper"]
CMD ["--help"]
