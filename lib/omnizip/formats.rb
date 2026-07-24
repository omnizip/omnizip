# frozen_string_literal: true


require "omnizip"
module Omnizip
  module Formats
    autoload :FormatSpecLoader, "omnizip/formats/format_spec_loader"

    autoload :SevenZip, "omnizip/formats/seven_zip"
    autoload :Zip, "omnizip/formats/zip"
    autoload :Rar, "omnizip/formats/rar"
    autoload :Tar, "omnizip/formats/tar"
    autoload :Gzip, "omnizip/formats/gzip"
    autoload :Bzip2File, "omnizip/formats/bzip2_file"
    autoload :Xz, "omnizip/formats/xz"

    autoload :Cpio, "omnizip/formats/cpio"
    autoload :Rpm, "omnizip/formats/rpm"
    autoload :Ole, "omnizip/formats/ole"
    autoload :Msi, "omnizip/formats/msi"
    autoload :Xar, "omnizip/formats/xar"
    autoload :Iso, "omnizip/formats/iso"
    autoload :LzmaAlone, "omnizip/formats/lzma_alone"
    autoload :Lzip, "omnizip/formats/lzip"

    autoload :XzConst, "omnizip/formats/xz_const"
    autoload :XzImpl, "omnizip/formats/xz_impl"
  end
end
