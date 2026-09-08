#!/usr/bin/env bash
# =============================================================================
# SharkVNTyper — detection of MUC1 VNTR insertions from exome data
#
#   1. shark   : keeps the R1/R2 read pairs sharing k-mers with MUC1 sequences
#   2. VNtyper : genotypes the VNTR on the filtered reads (Kestrel, k-mer mode)
#
# Designed to run INSIDE the SharkVNTyper docker image (shark, VNtyper, fastp,
# Kestrel and their dependencies installed). Default paths are those of the
# image (see Dockerfile); all of them can be overridden by an option or by a
# SHARKVNTYPER_* environment variable.
#
# Minimal usage:
#   sharkvntyper -1 SAMPLE_R1.fastq.gz -2 SAMPLE_R2.fastq.gz -o /data/out
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2023-2026, Sorbonne Université, Inserm U1155, Nephrogenomics team (Pr Laurent Mesnard)
# shark (GPL-3.0), VNtyper (BSD-3-Clause) and Kestrel (LGPL-3.0) are third-party
# programs called by this script: see THIRD_PARTY_LICENSES.md.
# =============================================================================
set -euo pipefail

VERSION="1.2.0"

# -----------------------------------------------------------------------------
# Defaults (overridable by environment variable, then by option)
# -----------------------------------------------------------------------------
SHARK_BIN="${SHARKVNTYPER_SHARK_BIN:-shark}"
VNTYPER_PY="${SHARKVNTYPER_VNTYPER_PY:-/opt/sharkvntyper/vntyper/vntyper.py}"
VNTYPER_DIR="${SHARKVNTYPER_VNTYPER_DIR:-/opt/sharkvntyper/vntyper/}"
SHARK_REF="${SHARKVNTYPER_SHARK_REF:-/opt/sharkvntyper/ref/muc1_seqs.fasta}"
REF_VNTR="${SHARKVNTYPER_REF_VNTR:-/opt/sharkvntyper/vntyper/Files/MUC1-VNTR.fa}"
# Genome reference (VNtyper -ref): not needed with --skip_alignment
# (vntyper.py modification M2), only required with --advntr.
REF_GENOME="${SHARKVNTYPER_REF:-}"
PYTHON_BIN="${SHARKVNTYPER_PYTHON:-python3}"

R1=""
R2=""
SAMPLE=""
OUTDIR="./sharkvntyper_out"
THREADS=8
KMER=21
KEEP_TEMP=0
RUN_ADVNTR=0
DEDUP=0
FORCE=0
DRY_RUN=0

# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
SharkVNTyper v${VERSION} — shark + VNtyper on a pair of FASTQ files (exome)

Usage: $(basename "$0") -1 R1.fastq.gz -2 R2.fastq.gz [options]

Inputs (required):
  -1, --r1 FILE          FASTQ read 1 (gzipped or not)
  -2, --r2 FILE          FASTQ read 2 (gzipped or not)

Output:
  -o, --outdir DIR       output directory              [${OUTDIR}]
  -s, --sample NAME      sample name                   [derived from the R1 file
                                                        name, part before the first "_"]
  -f, --force            overwrite OUTDIR/<sample> if it already exists

Parameters:
  -t, --threads N        threads for shark / fastp     [${THREADS}]
  -k, --kmer N           shark k-mer size (max 31)     [${KMER}]
      --keep-temp        keep the sharked FASTQ files and the .ssv
      --dedup            give Kestrel the fastp-filtered/deduplicated reads
                         (--use_qc_reads, VNtyper 1.3.0 behaviour) instead of
                         the raw sharked reads (VNtyper 1.1.0/1.2.0 behaviour)
      --advntr           full upstream mode (bwa alignment + adVNTR); NOT
                         supported by the docker image v${VERSION} (requires
                         advntr, bwa, picard, sambamba, samtools, -ref and -m)

References / tools (defaults = docker image):
      --shark-ref FILE   FASTA of the MUC1 sequences used by shark
                                                       [${SHARK_REF}]
      --ref-vntr FILE    MUC1 VNTR FASTA (-ref_VNTR)
                                                       [${REF_VNTR}]
      --ref FILE         genome reference (-ref), only required with --advntr
      --vntyper FILE     VNtyper script                [${VNTYPER_PY}]
      --vntyper-dir DIR  VNtyper directory (-p, contains Files/)
                                                       [${VNTYPER_DIR}]
      --shark-bin FILE   shark binary                  [${SHARK_BIN}]
      --python FILE      python interpreter            [${PYTHON_BIN}]

Misc:
      --dry-run          print the commands without running them
  -h, --help             this help
  -v, --version          version

Equivalent environment variables: SHARKVNTYPER_SHARK_BIN,
SHARKVNTYPER_VNTYPER_PY, SHARKVNTYPER_VNTYPER_DIR, SHARKVNTYPER_SHARK_REF,
SHARKVNTYPER_REF, SHARKVNTYPER_REF_VNTR, SHARKVNTYPER_PYTHON.

Outputs in OUTDIR:
  <sample>/<sample>_Final_result.tsv    VNtyper result
  <sample>/temp/                        VNtyper log, fastp report, Kestrel haplotypes (.sam)
  <sample>_sharkvntyper_summary.tsv     "Insertion" lines of the Final_result
  logs/<sample>.log, logs/<sample>.err  logs of this script
Exit codes: 0 = OK (with or without insertion), 1 = usage error,
2 = missing file/tool, 3 = shark failure, 4 = VNtyper failure.
EOF
}

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die()  { echo "ERROR: $1" >&2; exit "${2:-1}"; }

# Run a command (or print it with --dry-run)
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -n "[dry-run] "; printf '%q ' "$@"; echo
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------------
# Option parsing
# -----------------------------------------------------------------------------
[[ $# -eq 0 ]] && { usage; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -1|--r1)          R1="$2"; shift 2 ;;
        -2|--r2)          R2="$2"; shift 2 ;;
        -o|--outdir)      OUTDIR="$2"; shift 2 ;;
        -s|--sample)      SAMPLE="$2"; shift 2 ;;
        -f|--force)       FORCE=1; shift ;;
        -t|--threads)     THREADS="$2"; shift 2 ;;
        -k|--kmer)        KMER="$2"; shift 2 ;;
        --advntr)         RUN_ADVNTR=1; shift ;;
        --keep-temp)      KEEP_TEMP=1; shift ;;
        --dedup)          DEDUP=1; shift ;;
        --shark-ref)      SHARK_REF="$2"; shift 2 ;;
        --ref)            REF_GENOME="$2"; shift 2 ;;
        --ref-vntr)       REF_VNTR="$2"; shift 2 ;;
        --vntyper)        VNTYPER_PY="$2"; shift 2 ;;
        --vntyper-dir)    VNTYPER_DIR="$2"; shift 2 ;;
        --shark-bin)      SHARK_BIN="$2"; shift 2 ;;
        --python)         PYTHON_BIN="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        -v|--version)     echo "SharkVNTyper ${VERSION}"; exit 0 ;;
        --)               shift; break ;;
        -*)               die "unknown option: $1 (see --help)" 1 ;;
        *)                die "unexpected argument: $1 (see --help)" 1 ;;
    esac
done

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------
[[ -n "$R1" ]] || die "-1/--r1 is required" 1
[[ -n "$R2" ]] || die "-2/--r2 is required" 1
[[ "$THREADS" =~ ^[0-9]+$ ]] || die "--threads must be an integer" 1
[[ "$KMER" =~ ^[0-9]+$ && "$KMER" -le 31 ]] || die "--kmer must be an integer <= 31 (shark limit)" 1

for f in "$R1" "$R2" "$SHARK_REF" "$REF_VNTR" "$VNTYPER_PY"; do
    [[ -f "$f" ]] || die "file not found: $f" 2
done
[[ -d "$VNTYPER_DIR" ]] || die "VNtyper directory not found: $VNTYPER_DIR" 2
[[ -f "$VNTYPER_DIR/Files/MUC1_motifs_Rev_com.fa" && -f "$VNTYPER_DIR/Files/code-adVNTR_RUs.fa" ]] \
    || die "Files/MUC1_motifs_Rev_com.fa and Files/code-adVNTR_RUs.fa expected in $VNTYPER_DIR (vntyper.py, -p + 'Files/')" 2
KESTREL_JAR=/usr/local/lib/kestrel-1.0.1/kestrel.jar   # hard-coded in vntyper.py (kmer_command_k20)
if [[ $DRY_RUN -eq 0 ]]; then
    command -v "$SHARK_BIN"  >/dev/null 2>&1 || die "shark not found: $SHARK_BIN" 2
    command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "python not found: $PYTHON_BIN" 2
    command -v fastp >/dev/null 2>&1 || die "fastp not found in PATH (required by VNtyper --fastq)" 2
    command -v java  >/dev/null 2>&1 || die "java not found in PATH (required by Kestrel)" 2
    [[ -f "$KESTREL_JAR" ]] || die "Kestrel not found: $KESTREL_JAR (path imposed by VNtyper)" 2
fi

if [[ $RUN_ADVNTR -eq 1 ]]; then
    [[ -n "$REF_GENOME" && -f "$REF_GENOME" ]] || die "--advntr requires --ref <bwa-indexed chr1.fa>" 2
    REF_GENOME="$(readlink -f "$REF_GENOME")"
fi

# Sample name: part of the R1 file name before the first "_"
if [[ -z "$SAMPLE" ]]; then
    SAMPLE="$(basename "$R1")"
    SAMPLE="${SAMPLE%%_*}"
fi
[[ -n "$SAMPLE" ]] || die "cannot derive the sample name, use --sample" 1

# Absolute paths
R1="$(readlink -f "$R1")"
R2="$(readlink -f "$R2")"
SHARK_REF="$(readlink -f "$SHARK_REF")"
REF_VNTR="$(readlink -f "$REF_VNTR")"
VNTYPER_PY="$(readlink -f "$VNTYPER_PY")"
VNTYPER_DIR="$(readlink -f "$VNTYPER_DIR")/"   # VNtyper concatenates -p + 'Files/...': trailing "/" required

mkdir -p "$OUTDIR"
OUTDIR="$(readlink -f "$OUTDIR")"
TMPDIR_RUN="$OUTDIR/temp_${SAMPLE}"
LOGDIR="$OUTDIR/logs"
# VNtyper writes into <-w><-o> (string concatenation): -w "$OUTDIR/" -o "$SAMPLE"
VNT_RESULT_DIR="$OUTDIR/$SAMPLE"
FINAL_TSV="$VNT_RESULT_DIR/${SAMPLE}_Final_result.tsv"

# The VNtyper directory must not be reused (intermediate files and logs accumulate)
if [[ -e "$VNT_RESULT_DIR" ]]; then
    if [[ $FORCE -eq 1 ]]; then
        rm -rf "$VNT_RESULT_DIR"
    else
        die "$VNT_RESULT_DIR already exists (use --force to overwrite)" 1
    fi
fi
mkdir -p "$TMPDIR_RUN" "$LOGDIR"

LOG="$LOGDIR/${SAMPLE}.log"
ERR="$LOGDIR/${SAMPLE}.err"

# Temporary files cleanup (unless --keep-temp), also on error
cleanup() {
    if [[ $KEEP_TEMP -eq 0 ]]; then
        rm -rf "$TMPDIR_RUN"
    fi
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Pipeline
# -----------------------------------------------------------------------------
{
log "SharkVNTyper v${VERSION} — sample: $SAMPLE"
log "R1      : $R1"
log "R2      : $R2"
log "outdir  : $OUTDIR"
log "threads : $THREADS | shark k-mer: $KMER | Kestrel reads: $([[ $DEDUP -eq 1 ]] && echo 'fastp (deduplicated)' || echo 'raw sharked') | adVNTR: $RUN_ADVNTR"

# --- 1. shark ---------------------------------------------------------------
R1_SHARKED="$TMPDIR_RUN/${SAMPLE}-sharked_1.fastq"
R2_SHARKED="$TMPDIR_RUN/${SAMPLE}-sharked_2.fastq"
SSV="$TMPDIR_RUN/${SAMPLE}-sharked.ssv"

log "[1/2] shark"
if [[ $DRY_RUN -eq 1 ]]; then
    run "$SHARK_BIN" -r "$SHARK_REF" -1 "$R1" -2 "$R2" -k "$KMER" -t "$THREADS" \
        -o "$R1_SHARKED" -p "$R2_SHARKED"
else
    "$SHARK_BIN" -r "$SHARK_REF" -1 "$R1" -2 "$R2" -k "$KMER" -t "$THREADS" \
        -o "$R1_SHARKED" -p "$R2_SHARKED" > "$SSV" \
        || die "shark failed (see $ERR)" 3
    [[ -s "$R1_SHARKED" && -s "$R2_SHARKED" ]] \
        || die "shark produced no filtered read for $SAMPLE" 3
    log "sharked reads: $(( $(wc -l < "$R1_SHARKED") / 4 )) pairs"
fi

# --- 2. VNtyper -------------------------------------------------------------
# --ignore_advntr + --skip_alignment (M3) = fastp then Kestrel on the sharked reads;
# with --advntr: full upstream mode, -ref required
VNT_OPT=(--ignore_advntr --skip_alignment)
[[ $DEDUP -eq 1 ]] && VNT_OPT+=(--use_qc_reads)
REF_OPT=()
if [[ $RUN_ADVNTR -eq 1 ]]; then
    VNT_OPT=()
    REF_OPT=(-ref "$REF_GENOME")
fi

log "[2/2] VNtyper ($(basename "$VNTYPER_PY"))"
run "$PYTHON_BIN" "$VNTYPER_PY" --fastq \
    -r1 "$R1_SHARKED" -r2 "$R2_SHARKED" \
    -o "$SAMPLE" \
    -ref_VNTR "$REF_VNTR" \
    -t "$THREADS" \
    -p "$VNTYPER_DIR" \
    -w "$OUTDIR/" \
    ${REF_OPT[@]+"${REF_OPT[@]}"} ${VNT_OPT[@]+"${VNT_OPT[@]}"} \
    || die "VNtyper failed (see $ERR)" 4

# --- 3. Summary -------------------------------------------------------------
SUMMARY="$OUTDIR/${SAMPLE}_sharkvntyper_summary.tsv"
if [[ $DRY_RUN -eq 0 ]]; then
    # VNtyper does not propagate Kestrel errors (Popen without return code
    # check): check that the final result exists
    [[ -f "$FINAL_TSV" ]] \
        || die "VNtyper result not found: $FINAL_TSV (see $VNT_RESULT_DIR/temp/VNtyper.logfile.log)" 4
    # "Insertion" lines of the final result
    grep -h "Insertion" "$FINAL_TSV" > "$SUMMARY" || true
    n_ins=$(wc -l < "$SUMMARY")
    if [[ $n_ins -gt 0 ]]; then
        log "RESULT: $n_ins MUC1 insertion(s) detected -> $SUMMARY"
    else
        log "RESULT: no MUC1 insertion detected"
    fi
fi

log "done: $VNT_RESULT_DIR"
} > >(tee -a "$LOG") 2> >(tee -a "$ERR" >&2)

exit 0
