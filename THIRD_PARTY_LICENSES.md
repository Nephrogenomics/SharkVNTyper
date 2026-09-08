# Third-party licenses

SharkVNTyper's own code (`sharkvntyper.sh`, `Dockerfile`, `README.md`,
`requirements.txt`) is distributed under the BSD 3-Clause License (see
`LICENSE`). It bundles or downloads the following components, each under its
own license, kept unchanged.

| Component | Version | License | Location in this repository / in the image | Source |
|---|---|---|---|---|
| shark | AlgoLab/shark v1.2.0 + 1 commit (feee4d8, 2020-12-09 = upstream HEAD; identical sources) | GPL-3.0 | `shark/` (unmodified sources) → `/usr/local/bin/shark` | https://github.com/AlgoLab/shark |
| sdsl-lite | 2.1.1 (bundled in shark) | GPL-3.0 | `shark/sdsl-lite/` (compiled at build time, not installed in the final image) | https://github.com/simongog/sdsl-lite |
| VNtyper | 1.3.0 (tag `VNtyper_v1.3.0`), **modified** | BSD-3-Clause (Hassan Saei, Université Paris Cité / Imagine Institute, 2023) | `vntyper/vntyper.py` (modifications listed in the file header and in `vntyper/CHANGES_vs_upstream_1.3.0.diff`), `vntyper/VNtyper_1.3.0_upstream.py` (pristine upstream copy), `vntyper/Files/` (identical to upstream), `vntyper/LICENSE` | https://github.com/hassansaei/VNtyper |
| Kestrel | 1.0.1 | LGPL-3.0 (`COPYING`, `COPYING.LESSER` in the archive) | downloaded at build time → `/usr/local/lib/kestrel-1.0.1/` (jars + licenses) | https://github.com/paudano/kestrel |
| fastp | Ubuntu 24.04 package (0.23.4) | MIT (Expat) | installed by apt | https://github.com/OpenGene/fastp |
| OpenJDK | 17 (Ubuntu package) | GPL-2.0 with Classpath Exception | installed by apt | https://openjdk.org |
| pandas, numpy, regex, biopython, pysam | see `requirements.txt` | BSD-3 / BSD-3 / Apache-2.0 / Biopython License ("freely distributable") / MIT | installed by pip (package metadata) | PyPI |

## Terms of use

- **shark / sdsl-lite (GPL-3.0)**: complete sources provided in `shark/`;
  shark is invoked as a separate executable by `sharkvntyper.sh` (aggregation).
  Any modification of the shark sources must remain under GPL-3.0 and be
  published.
- **VNtyper (BSD-3-Clause)**: copyright notice and license kept
  (`vntyper/LICENSE`); modifications are identified (`SharkVNTyper M1..M5`
  markers in `vntyper/vntyper.py` and diff file). The names of the VNtyper
  authors or of the Imagine Institute must not be used to endorse or promote
  SharkVNTyper without permission (clause 3).
- **Kestrel (LGPL-3.0)**: used unmodified, called as an external program
  (`java -jar`) by VNtyper; archive and licenses kept in the image.

## Reference data

- `vntyper/Files/MUC1-VNTR.fa`, `.fai`, `MUC1_motifs_Rev_com.fa`,
  `code-adVNTR_RUs.fa`: provided by VNtyper (BSD-3-Clause), unchanged.
- `ref/muc1_seqs.fasta` (shark reference): curated set of high-quality MUC1
  alleles from previous publications, built by the team (Bensouna *et al.*,
  JASN 2025); distributed under the repository license (BSD-3-Clause), see
  `ref/README.md`.

## Citations

SharkVNTyper itself: Bensouna I, *et al.* Systematic Screening of Autosomal
Dominant Tubulointerstitial Kidney Disease-MUC1 27dupC Pathogenic Variant
through Exome Sequencing. *J Am Soc Nephrol* 2025;36(2):256–263.
doi:10.1681/ASN.0000000503 (see `CITATION.cff`).

Third-party tools:

- Saei H, *et al.* VNtyper enables accurate alignment-free genotyping of MUC1
  coding VNTR using short-read sequencing data in autosomal dominant
  tubulointerstitial kidney disease. *iScience* 2023;26(7):107171.
  doi:10.1016/j.isci.2023.107171
- Denti L, *et al.* Shark: fishing relevant reads in an RNA-Seq sample.
  *Bioinformatics* 2021;37(4):464–472. doi:10.1093/bioinformatics/btaa779
- Audano PA, Ravishankar S, Vannberg FO. Mapping-free variant calling using
  haplotype reconstruction from k-mer frequencies. *Bioinformatics*
  2018;34(10):1659–1665. doi:10.1093/bioinformatics/btx753
- Chen S, Zhou Y, Chen Y, Gu J. fastp: an ultra-fast all-in-one FASTQ
  preprocessor. *Bioinformatics* 2018;34(17):i884–i890.
  doi:10.1093/bioinformatics/bty560
