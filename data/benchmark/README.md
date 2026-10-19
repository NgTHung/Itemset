# Benchmark data

The experiments measure the miner on four standard frequent-itemset databases: Chess, Mushroom, Retail, and T10I4D100K. The files are too large for the repository, so this folder holds local copies that Git ignores, and the README links their public mirrors.

Download from a public Hugging Face or Kaggle mirror, as the brief requires. Verify each file's bytes against the [SPMF dataset catalog](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php) or [FIMI](http://fimi.uantwerpen.be/data/) before you use it.

Commit a small manifest per dataset with:

- name and version,
- source URL and mirror URL,
- license or usage terms,
- filename and SHA-256,
- transaction count, distinct-item count, and mean width, computed from the file,
- any preprocessing.

Download and preparation code lives in the notebook modules, so a clean Colab run rebuilds this folder.
