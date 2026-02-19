# RAR Write Support Documentation

## Overview

The key distinction:

RAR format structure = Publicly documented, implementable ✅
WinRAR's specific compression = Proprietary ❌

## Important Licensing Information

WinRAR is owned by Alexander Roshal and RARLAB. Creating RAR archives using WinRAR requires:

1. **A valid WinRAR license** - Purchase from https://www.rarlab.com/
2. **WinRAR installation** - The command-line tool must be installed

RAR format structure = Publicly documented, implementable ✅
WinRAR's specific compression = Proprietary ❌

### Why Not Built-In?

Unlike formats such as ZIP, 7z, TAR, etc., there is a confusion that RAR compression cannot be implemented freely due to:

- Proprietary algorithm patents: but there are NO patents on RAR compression algorithms
- Licensing restrictions from RARLAB: the RAR format structure is publicly documented, implementable, and already implemented independently in libarchive which is fully open source.
- Legal risks of reverse engineering: the RAR format structure is documented and does not require reverse engineering.
