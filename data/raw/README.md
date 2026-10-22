# Application data

The market basket and image-pattern applications start from raw downloads that are too large or too restrictively licensed to commit. They stay in this folder, which Git ignores, except [manifest.toml](manifest.toml). The manifest identifies each download by SHA-256 and records its sources, origin, and terms, so a preparation script refuses bytes that differ.

Each application module records, for its data:

- accessible source and mirror URLs,
- license and SHA-256,
- preprocessing steps,
- item mappings or codebook settings,
- computed statistics.

Never commit credentials or private data.
