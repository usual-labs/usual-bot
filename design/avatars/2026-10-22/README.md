# Usual Bot avatar collection

50 original assistant characters inspired by the supplied reference sheets. Generated with the built-in image-generation tool, one image per character. The original RGBA PNGs are preserved without resizing, recoloring, or post-processing.

- `CHARACTERS.md`: all personalities, roles, quirks, and visual descriptions, written before generation.
- `REFERENCE-STUDY.md`: observations from both references and visual direction.
- `characters.json`: machine-readable catalogue and PNG paths.
- `prompts.json`: generation prompts and the targeted correction used for Pebble.
- `png/`: individual PNG avatars.
- `index.html`: local gallery, with light/dark preview backgrounds.
- `references/`: copies of both user-supplied style sheets.
- `receipts/`: source image paths and individual visual-review notes.
- `verification.json`: image dimensions, transparency checks, margins, hashes, and catalogue/gallery mapping.

Open `index.html` locally to browse the collection, search by name or role, switch preview backgrounds, and download individual PNGs. It is self-contained and needs no server or network connection. The gallery was checked statically; no browser testing was performed.

The image prompts requested 1024×1024, but the built-in tool returned native 1254×1254 files. Those original dimensions and alpha channels are retained. Character concepts and personality profiles were completed before the first generation. The base character descriptions are concept briefs; individual illustrations may simplify accessories.

These are art assets only; no application behavior or avatar-selection UI is changed.


## In this repository

The app uses 256×256 copies of these characters, in `Packages/UsualUI/Sources/UsualUI/Resources/Avatars/avatar-<slug>.png`. The full-size originals (`png/`), their zip, the reference sheets (`references/`) and the generation receipts (`receipts/`, which record local paths) are not committed, so `index.html` and the `png/` links above only work in the designer's own copy.

## Lossless compressed versions

`png/lossless/` contains smaller 1254×1254 derivatives of all 50 originals: 20,251,946 bytes reduced to 16,203,100 bytes (19.99%). The original files and archive remain unchanged. The app's existing 256×256 resources were compressed in place, reducing their total from 1,377,948 to 1,176,884 bytes (14.59%).

Every decoded RGBA byte, dimension, and rendering metadata chunk was compared before accepting the compressed versions. There is no resizing, color quantization, or alpha change. Non-rendering content credentials tied to the original encoding are omitted from full-size derivatives; they remain in the original images. All other metadata is preserved. See `lossless-compression-report.json` for individual sizes and hashes.

The separate `../usual-bot-50-avatars-lossless.zip` contains the compressed full-size PNGs, profiles, prompts, and a gallery that downloads those compressed files.
