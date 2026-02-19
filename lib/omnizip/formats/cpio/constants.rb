# frozen_string_literal: true

module Omnizip
  module Formats
    module Cpio
      # CPIO format constants
      #
      # Defines magic numbers, file types, and format specifications
      # for different CPIO archive formats.
      module Constants
        # Magic numbers for different CPIO formats
        MAGIC_BINARY = 0o070707 # Old binary format
        MAGIC_ODC = "070707"   # Old portable ASCII format
        MAGIC_NEWC = "070701"  # New ASCII format (SVR4, most common)
        MAGIC_CRC = "070702"   # New ASCII with CRC

        # File type masks (from POSIX)
        S_IFMT = 0o170000   # File type mask
        S_IFSOCK = 0o140000 # Socket
        S_IFLNK = 0o120000  # Symbolic link
        S_IFREG = 0o100000  # Regular file
        S_IFBLK = 0o060000  # Block device
        S_IFDIR = 0o040000  # Directory
        S_IFCHR = 0o020000  # Character device
        S_IFIFO = 0o010000  # FIFO/pipe

        # Permission bits
        S_ISUID = 0o004000  # Set UID bit
        S_ISGID = 0o002000  # Set GID bit
        S_ISVTX = 0o001000  # Sticky bit
        S_IRWXU = 0o000700  # User permissions
        S_IRUSR = 0o000400  # User read
        S_IWUSR = 0o000200  # User write
        S_IXUSR = 0o000100  # User execute
        S_IRWXG = 0o000070  # Group permissions
        S_IRGRP = 0o000040  # Group read
        S_IWGRP = 0o000020  # Group write
        S_IXGRP = 0o000010  # Group execute
        S_IRWXO = 0o000007  # Other permissions
        S_IROTH = 0o000004  # Other read
        S_IWOTH = 0o000002  # Other write
        S_IXOTH = 0o000001  # Other execute

        # CPIO newc header size (110 bytes for newc format)
        NEWC_HEADER_SIZE = 110

        # Trailer entry name
        TRAILER_NAME = "TRAILER!!!"

        # Alignment for newc format (4 bytes)
        NEWC_ALIGNMENT = 4
      end
    end
  end
end
