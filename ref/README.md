# ref/

`muc1_seqs.fasta` — reference used by shark to retain MUC1 read pairs
(156 sequences `muc1_ref_1` … `muc1_ref_156`, 7.1 to 9.5 kb each, 1.13 Mb in
total, ACGT alphabet).

Construction (Bensouna *et al.*, JASN 2025, Methods): given the variability of
MUC1 sequences among individuals, a comprehensive set of high-quality MUC1
alleles was curated from previous publications (Kirby *et al.*, Nat Genet
2013, doi:10.1038/ng.2543; Wenzel *et al.*, Sci Rep 2018,
doi:10.1038/s41598-018-22428-0) and used as the basis for read filtering. Built by the team; distributed under the repository license
(BSD-3-Clause, see `../LICENSE`). Line endings normalised to LF (the original
file used CRLF; shark accepts both).

Copied into the image at `/opt/sharkvntyper/ref/muc1_seqs.fasta` by the
Dockerfile; can be overridden with `sharkvntyper --shark-ref` or
`SHARKVNTYPER_SHARK_REF`.
