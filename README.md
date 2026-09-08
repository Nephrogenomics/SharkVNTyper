# SharkVNTyper

Detection of insertions in the coding VNTR of *MUC1* (ADTKD-MUC1) from exome
data (paired-end FASTQ), in two steps:

1. **shark** (Denti *et al.*, Bioinformatics 2021) — alignment-free filtering
   of the read pairs sharing k-mers with MUC1 sequences (`ref/muc1_seqs.fasta`);
2. **VNtyper** (Saei *et al.*, iScience 2023) — k-mer genotyping of the VNTR
   with Kestrel. `vntyper/vntyper.py` is the upstream 1.3.0 version
   (BSD-3-Clause) with five documented modifications (M1–M5, listed in the file
   header), including a `--skip_alignment` mode that runs fastp and then
   Kestrel directly on the sharked reads, without bwa alignment.

Everything is packaged in a docker image and exposed through a single script,
`sharkvntyper`, that runs on one pair of FASTQ files.

## Use case

Autosomal dominant tubulointerstitial kidney disease due to *MUC1*
(ADTKD-MUC1) is caused in more than 80% of cases by a cytosine insertion in
the coding VNTR of *MUC1* ("27dupC"), which creates an 8C homopolymer between
positions 53 and 59 of the 60-bp repeat unit, a frameshift and a truncated
mucin-1 (Bensouna *et al.*, JASN 2025, and references therein). The VNTR is
made of 25 to 120 GC-rich 60-bp repeats whose number (30 to 80) and sequence
vary between individuals, so short reads align ambiguously or not at all to
the linear reference genome and the variant is missed by conventional
alignment-based exome analysis. Available diagnostic methods (SNaPshot PCR,
immunohistochemistry of the truncated protein on kidney biopsy) are not
designed for systematic screening, and VNtyper alone, built for targeted
panels at 300–500x, takes 6 to 12 hours per exome.

SharkVNTyper adapts VNtyper to exome-scale data by adding a filtering step:

1. **shark** reduces the whole exome FASTQ pair to the read pairs sharing
   k-mers with a curated set of high-quality MUC1 alleles
   (`ref/muc1_seqs.fasta`, curated from previous publications given the
   variability of MUC1 sequences among individuals);
2. **VNtyper** (Kestrel k-mer genotyping) is run on this small read set only.

Performance reported in Bensouna *et al.* (JASN 2025): in the proof-of-concept
cohort (33 SNaPshot-confirmed 27dupC carriers, 54 negative controls, exome
data at ~80x), SharkVNTyper identified 32/33 positives and excluded all 54
negatives (sensitivity 97%, specificity 100%), where VNtyper alone reached
33/33 and 54/54; the running time per sample dropped from 6–12 hours to 7.5 ±
2.5 minutes (VNtyper itself taking less than one minute on the filtered
reads). Systematic screening of 3,512 retrospective and 825 prospective
exomes from patients with chronic kidney disease found 36 positives, 30 of
them confirmed by SNaPshot PCR (positive predictive value 78% retrospectively,
92% prospectively; worst-case specificity 99.9%). The atypical 27insCCCC
insertion, which shares the same 8C homopolymer, was also detected. On genome
sequencing (~30x) the single positive control tested was missed, and the
tool was not validated on genomes.

SharkVNTyper is a **screening test**: any positive result must be confirmed by
an orthogonal diagnostic test (SNaPshot PCR), and in case of clinical
suspicion of ADTKD-MUC1 a negative screening result does not replace the
diagnostic test. Its ability to detect MUC1 variants other than 27dupC and
27insCCCC has not been established.

Input: one pair of paired-end FASTQ files per sample (gzipped or not), from
exome sequencing (validated) or genome sequencing (not validated, see above).
Unaligned BAM (uBAM) or complete aligned BAM files can be converted with
`samtools collate -u -O in.bam | samtools fastq -1 R1.fastq.gz -2 R2.fastq.gz -0 /dev/null -s /dev/null -n -`;
a BAM restricted to the MUC1 region or without its unmapped reads must not be
used, as part of the informative reads are unmapped or misaligned.

## History

- **v1 (October 2023)** — first version: shark → VNtyper 1.1.0 (Singularity
  image) driven by a weekly script over routine exomes, hard-coded paths.
- **v1.2 (2026)** — this version: per-sample command-line tool, docker image
  built from sources, VNtyper rebased on upstream 1.3.0 (BSD-3-Clause) with
  documented modifications, per-component licenses.

## Repository layout

```
Dockerfile          sharkvntyper image (multi-stage: shark build, then runtime)
sharkvntyper.sh     turnkey script (installed in the image as /usr/local/bin/sharkvntyper)
requirements.txt    VNtyper python dependencies (pinned versions for the build)
LICENSE             BSD-3-Clause (own code); THIRD_PARTY_LICENSES.md for third-party components
CITATION.cff        citation metadata
shark/              shark sources (GPL-3.0) + bundled sdsl-lite v2.1.1 (rebuilt at build time)
vntyper/            vntyper.py (modified VNtyper 1.3.0), VNtyper_1.3.0_upstream.py (pristine upstream copy),
                    CHANGES_vs_upstream_1.3.0.diff, LICENSE (BSD-3), Files/ (MUC1-VNTR.fa, motifs)
ref/                muc1_seqs.fasta — shark reference built by the team (see ref/README.md)
```

## Requirements

- Docker (Docker Engine or Docker Desktop). The build needs network access
  (Ubuntu packages, PyPI, Kestrel from GitHub); running does not.
- Memory: VNtyper starts Kestrel with `java -Xmx15g`, i.e. a 15 GB heap
  ceiling. On shark-filtered reads the actual use is usually much lower, but
  a machine with at least 16 GB of RAM is recommended.
- CPU: `-t` threads for shark and fastp (default 8); Kestrel is
  single-process. 4 threads are enough, 8 are faster on the shark step.
- Disk: the image is about 1 GB; per sample, the temporary sharked FASTQ files
  are a few MB and are deleted at the end (unless `--keep-temp`).

## Building the image

```bash
docker build -t sharkvntyper:1.2.0 .
```

The build compiles shark from sources (and checks the result against the
example shipped in `shark/example`), downloads Kestrel 1.0.1 from GitHub,
installs fastp and the JRE from the Ubuntu 24.04 repositories (fastp ≥ 0.22.0 is required for `--dedup`; the 22.04 package is too old), and the python
modules of `requirements.txt`.

## Usage

```bash
docker run --rm -v /data:/data sharkvntyper:1.2.0 \
    -1 /data/fastq/SAMPLE_R1.fastq.gz \
    -2 /data/fastq/SAMPLE_R2.fastq.gz \
    -o /data/results/2026-09-07 \
    -t 8
```

`-v /data:/data` mounts the host directory that contains the FASTQ files (and
where the results are written) inside the container; paths given to `-1`,
`-2` and `-o` are container paths, i.e. under the mount point. Add
`--memory 20g` to cap the memory the container may use (a safeguard on a
shared machine; not required). `--user $(id -u):$(id -g)` makes the output
files belong to you instead of root.

`sharkvntyper --help` lists all options. The main ones:

| option | role | default |
|---|---|---|
| `-1 / -2` | FASTQ R1 / R2 (gzipped accepted) | required |
| `-o` | output directory | `./sharkvntyper_out` |
| `-s` | sample name | part of the R1 file name before the first `_` |
| `-t` | threads for shark / fastp | 8 |
| `-k` | shark k-mer size (≤ 31) | 21 |
| `-f` | overwrite `OUTDIR/<sample>` if it exists | — |
| `--keep-temp` | keep the sharked FASTQ files and the `.ssv` | deleted |
| `--dedup` | Kestrel on the fastp-deduplicated reads (1.3.0 behaviour) instead of the raw sharked reads (1.1.0/1.2.0 behaviour, default) | no |
| `--shark-ref`, `--ref-vntr`, `--vntyper`, `--vntyper-dir` | override the files of the image | image paths |
| `--dry-run` | print the commands without running them | — |

Outputs in `OUTDIR`:

```
<sample>/<sample>_Final_result.tsv    VNtyper result (Kestrel)
<sample>/temp/                        VNtyper log, fastp report, Kestrel haplotypes (.sam)
<sample>_sharkvntyper_summary.tsv     "Insertion" lines of the final result (empty if none)
logs/<sample>.log, logs/<sample>.err  script logs
```

Exit codes: 0 OK (with or without insertion), 1 usage error, 2 missing
file/tool, 3 shark failure, 4 VNtyper failure (final result missing).

### Reading the result

`<sample>_Final_result.tsv` is the VNtyper table (header lines starting with
`#`, then one row per retained variant):

| column | meaning |
|---|---|
| `Motif` | MUC1 VNTR motif in which the variant lies (VNtyper motif dictionary, `Files/MUC1-VNTR.fa`) |
| `Variant` | `Insertion` or `Deletion` (frameshifts only: 3n+1 insertions, 3n+2 deletions) |
| `POS`, `REF`, `ALT` | position within the motif, reference and alternate alleles (27dupC appears as `C` → `CC`) |
| `Motif_sequence` | sequence of the motif |
| `Estimated_Depth_AlternateVariant` | Kestrel depth supporting the variant |
| `Estimated_Depth_Variant_ActiveRegion` | Kestrel depth of the active region |
| `Depth_Score` | ratio of the two depths |
| `Confidence` | `High_Precision`, `High_Precision*` or `Low_Precision` — VNtyper thresholds (`conditions()` in `vntyper.py`): `Low_Precision` if `Depth_Score` ≤ 0.00469, or active-region depth ≤ 200, or alternate depth ≤ 20, or 0.00469 ≤ `Depth_Score` ≤ 0.00515; otherwise `High_Precision` |
| `Kmer_Size` | Kestrel k-mer size (20) |

An empty table (header only) means no frameshift variant was retained.
`<sample>_sharkvntyper_summary.tsv` contains only the `Insertion` rows, for
quick screening of many samples. The `RESULT:` line of the log gives the
number of insertions.

### Batch example

```bash
for r1 in /data/fastq/*_R1.fastq.gz; do
    r2=${r1/_R1/_R2}
    docker run --rm --user $(id -u):$(id -g) -v /data:/data sharkvntyper:1.2.0 \
        -1 "$r1" -2 "$r2" -o /data/results/$(date +%F) -t 8
done
cat /data/results/$(date +%F)/*_sharkvntyper_summary.tsv
```

Each sample writes its own `<sample>/` directory and `<sample>_sharkvntyper_summary.tsv`
in the output directory; `logs/` gathers the per-sample logs.

## Running with Singularity / Apptainer

On servers where Docker is not available or containers cannot be built by
unprivileged users (e.g. rootless podman without sub-UID ranges), the image can
be converted into a single `.sif` file that runs without root privileges. Build
the image once with Docker or podman (with the required privileges), export it,
and convert it:

```bash
docker save sharkvntyper:1.2.0 -o sharkvntyper_1.2.0.tar        # or: sudo podman save localhost/sharkvntyper:1.2.0 -o ...
singularity build sharkvntyper_1.2.0.sif docker-archive://$PWD/sharkvntyper_1.2.0.tar
singularity run sharkvntyper_1.2.0.sif --version
```

The `.sif` file is self-contained and can be copied to any host with
Singularity/Apptainer. Run it with `--bind` in place of `docker run -v`; the
container runs under your own account, so output files belong to you and
`--user` is not needed:

```bash
singularity run --bind /data:/data sharkvntyper_1.2.0.sif \
    -1 /data/fastq/SAMPLE_R1.fastq.gz \
    -2 /data/fastq/SAMPLE_R2.fastq.gz \
    -o /data/results/2026-09-07 \
    -t 8
```

Tested with Apptainer on a RHEL server: conversion from a podman-built image
and execution as an unprivileged user.

## Modifications to VNtyper 1.3.0 and points of attention

`vntyper/vntyper.py` = `VNtyper_1.3.0_upstream.py` + :

- **M1** header and version `1.3.0+sharkvntyper.1`.
- **M2** `-ref` optional; new `--skip_alignment` option.
- **M3** with `--fastq --skip_alignment`: fastp (`--dedup --disable_adapter_trimming
  --length_required 40`, the FASTQ-mode parameters of versions 1.1.0/1.2.0)
  and then Kestrel, without bwa/picard/sambamba alignment; the VNTR coverage is
  `NA`. By default Kestrel reads the **raw** input reads, as versions
  1.1.0/1.2.0 did in FASTQ mode (there, the fastp output was only used for the
  QC report: `fastq_1`/`fastq_2` were reassigned in the BAM branch only); with
  `--use_qc_reads` (`--dedup` option of `sharkvntyper`), Kestrel reads the
  fastp-filtered/deduplicated reads, as in 1.3.0. Without `--skip_alignment`,
  the upstream FASTQ mode (alignment on `-ref`) is unchanged.
- **M4** guard in `StepA_processing`: a Kestrel VCF without any indel no longer
  crashes the script (upstream `ValueError`) and yields an empty result.
- **M5** `rm -f` when cleaning intermediate files.

Behaviours inherited from upstream, handled by `sharkvntyper.sh`:

- hard-coded Kestrel path (`/usr/local/lib/kestrel-1.0.1/kestrel.jar`);
- `-p` must end with `/` (concatenated with `Files/`);
- the output directory is `-w` + `-o` concatenated;
- Kestrel errors are not propagated (`Popen` without return-code check): the
  script checks that `<sample>_Final_result.tsv` exists;
- adVNTR is not included in the image (python2 / singularity); `--advntr` is
  therefore not functional in image v1.2.0.

**Differences with the 1.1.0 version used in production so far.** On the
synthetic dataset below, the default mode (raw reads) reproduces the 1.1.0
result exactly (`624 / 4434 / 0.14073`). With `--dedup`, depths change
(`435 / 2707 / 0.16069`) and Kestrel additionally calls an insertion at an
artificial junction between concatenated motifs: as the confidence thresholds
(depth ≥ 21, active region > 200, `Depth_Score`) were established on
non-deduplicated depths, `--dedup` must not be used without revalidation.
Besides, the Kestrel post-processing of versions ≥ 1.2.0 differs from 1.1.0 on
three points (`ALT == "GG"` tested with the regex `\bGG\b` instead of the `GG`
substring, exclusion of `CG`/`TG` ALTs when both coexist, deduplication by ALT
of the right-half motif calls outside the `GG` case); these differences are not
exercised by the synthetic dataset. Revalidation on known positive and negative
samples is required before any routine use.

## Validation

The validation of SharkVNTyper (proof-of-concept, retrospective and prospective
exome cohorts) is described in Bensouna *et al.*, JASN 2025 (see "How to
cite"). This version was additionally checked on the shark upstream example,
on synthetic reads and on known positive and negative exomes, with results
consistent with the published pipeline.

## How to cite

SharkVNTyper:

- Bensouna I, Robert T, Vanhoye X, Dancer M, Raymond L, Delaugère P, Hilbert P,
  Richard H, Mesnard L. Systematic Screening of Autosomal Dominant
  Tubulointerstitial Kidney Disease-MUC1 27dupC Pathogenic Variant through
  Exome Sequencing. *J Am Soc Nephrol* 2025;36(2):256–263.
  doi:10.1681/ASN.0000000503. PMID 39325540, PMCID PMC11801747.

Please also cite the tools it relies on (below).

## References

- Saei H, *et al.* VNtyper enables accurate alignment-free genotyping of MUC1
  coding VNTR using short-read sequencing data in autosomal dominant
  tubulointerstitial kidney disease. *iScience* 2023;26(7):107171.
  doi:10.1016/j.isci.2023.107171
- Denti L, *et al.* Shark: fishing relevant reads in an RNA-Seq sample.
  *Bioinformatics* 2021;37(4):464–472. doi:10.1093/bioinformatics/btaa779
- Audano PA, Ravishankar S, Vannberg FO. Mapping-free variant calling using
  haplotype reconstruction from k-mer frequencies. *Bioinformatics*
  2018;34(10):1659–1665. doi:10.1093/bioinformatics/btx753

## License

Own code: BSD-3-Clause (`LICENSE`). Third-party components keep their own
licenses: see `THIRD_PARTY_LICENSES.md`.
