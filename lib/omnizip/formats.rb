# frozen_string_literal: true

module Omnizip
  module Formats
    # Archive format support
    #
    # This module contains format-specific autoload declarations.
    # Less commonly used formats are autoloaded for lazy loading.

    # Format specification loader
    autoload :FormatSpecLoader, "omnizip/formats/format_spec_loader"

    # CPIO archive format
    autoload :Cpio, "omnizip/formats/cpio"

    # RPM package format
    autoload :Rpm, "omnizip/formats/rpm"

    # OLE compound documents (MSI, DOC, XLS, PPT)
    autoload :Ole, "omnizip/formats/ole"

    # MSI (Microsoft Installer) - overrides OLE's .msi registration
    autoload :Msi, "omnizip/formats/msi"

    # XAR archive format
    autoload :Xar, "omnizip/formats/xar"

    # ISO 9660 CD-ROM format
    autoload :Iso, "omnizip/formats/iso"

    # LZMA alone format
    autoload :LzmaAlone, "omnizip/formats/lzma_alone"

    # LZIP format
    autoload :Lzip, "omnizip/formats/lzip"

    # XZ format constants (at Formats level for cross-module access)
    autoload :XzConst, "omnizip/formats/xz_const"

    # XZ implementation details
    autoload :XzImpl, "omnizip/formats/xz_impl"
  end
end
