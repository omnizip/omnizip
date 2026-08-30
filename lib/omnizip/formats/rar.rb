# frozen_string_literal: true

module Omnizip
  module Formats
    # RAR archive format support
    #
    # - Formats::Rar::Reader — the primary parser, verified against
    #   real WinRAR archives: listing, directories, mtimes, and
    #   extraction (native STORE decode with stored-CRC verification;
    #   foreign compressed streams fall back to the unrar command
    #   after the CRC check rejects them)
    # - Formats::Rar::Writer (RAR4) and Formats::Rar::Rar5::Writer —
    #   STORE output is unrar-verified; compressed methods produce
    #   Omnizip-internal streams (see the README interop table)
    # - Formats::Rar3 / Formats::Rar5 — legacy interfaces, thin
    #   adapters over the primary reader and the RAR5 writer
    # - Multi-volume archives, encryption (RAR5), recovery records
    module Rar
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/formats/rar/constants"
      autoload :Header, "omnizip/formats/rar/header"
      autoload :BlockParser, "omnizip/formats/rar/block_parser"
      autoload :Decompressor, "omnizip/formats/rar/decompressor"
      autoload :VolumeManager, "omnizip/formats/rar/volume_manager"
      autoload :RecoveryRecord, "omnizip/formats/rar/recovery_record"
      autoload :ParityHandler, "omnizip/formats/rar/parity_handler"
      autoload :ArchiveVerifier, "omnizip/formats/rar/archive_verifier"
      autoload :ArchiveRepairer, "omnizip/formats/rar/archive_repairer"
      autoload :Reader, "omnizip/formats/rar/reader"
      autoload :Writer, "omnizip/formats/rar/writer"
      autoload :RarFormatBase, "omnizip/formats/rar/rar_format_base"
      autoload :ExternalWriter, "omnizip/formats/rar/external_writer"
      autoload :LicenseValidator, "omnizip/formats/rar/license_validator"
      # Models
      autoload :Models, "omnizip/formats/rar/models"
      # RAR5 support
      module Rar5
        autoload :VINT, "omnizip/formats/rar/rar5/vint"
        autoload :CRC32, "omnizip/formats/rar/rar5/crc32"
        autoload :Header, "omnizip/formats/rar/rar5/header"
        # MainHeader/FileHeader live in header.rb directly under Rar5;
        # without their own autoload entries, referencing them only
        # works if something else loaded the file first.
        autoload :MainHeader, "omnizip/formats/rar/rar5/header"
        autoload :FileHeader, "omnizip/formats/rar/rar5/header"
        autoload :Writer, "omnizip/formats/rar/rar5/writer"
        # RAR5 compression
        module Compression
          autoload :Store, "omnizip/formats/rar/rar5/compression/store"
          autoload :Lzma, "omnizip/formats/rar/rar5/compression/lzma"
          autoload :Lzss, "omnizip/formats/rar/rar5/compression/lzss"
        end

        # RAR5 multi-volume
        module MultiVolume
          autoload :VolumeManager,
                   "omnizip/formats/rar/rar5/multi_volume/volume_manager"
          autoload :VolumeWriter,
                   "omnizip/formats/rar/rar5/multi_volume/volume_writer"
          autoload :VolumeSplitter,
                   "omnizip/formats/rar/rar5/multi_volume/volume_splitter"
        end

        # RAR5 models
        module Models
          autoload :VolumeOptions,
                   "omnizip/formats/rar/rar5/models/volume_options"
          autoload :SolidOptions,
                   "omnizip/formats/rar/rar5/models/solid_options"
          autoload :EncryptionOptions,
                   "omnizip/formats/rar/rar5/models/encryption_options"
          autoload :RecoveryOptions,
                   "omnizip/formats/rar/rar5/models/recovery_options"
        end

        # RAR5 solid compression
        module Solid
          autoload :SolidManager, "omnizip/formats/rar/rar5/solid/solid_manager"
          autoload :SolidEncoder, "omnizip/formats/rar/rar5/solid/solid_encoder"
          autoload :SolidStream, "omnizip/formats/rar/rar5/solid/solid_stream"
        end

        # RAR5 encryption
        module Encryption
          autoload :Aes256Cbc, "omnizip/formats/rar/rar5/encryption/aes256_cbc"
          autoload :EncryptionHeader,
                   "omnizip/formats/rar/rar5/encryption/encryption_header"
          autoload :KeyDerivation,
                   "omnizip/formats/rar/rar5/encryption/key_derivation"
          autoload :EncryptionManager,
                   "omnizip/formats/rar/rar5/encryption/encryption_manager"
        end

        # RAR5 compression
        module Compression
          autoload :Store, "omnizip/formats/rar/rar5/compression/store"
          autoload :Lzma, "omnizip/formats/rar/rar5/compression/lzma"
          autoload :Lzss, "omnizip/formats/rar/rar5/compression/lzss"
        end
      end

      # Compression layer
      module Compression
        autoload :BitStream, "omnizip/formats/rar/compression/bit_stream"
        autoload :Dispatcher, "omnizip/formats/rar/compression/dispatcher"
        module PPMd
          autoload :Context, "omnizip/formats/rar/compression/ppmd/context"
          autoload :Decoder, "omnizip/formats/rar/compression/ppmd/decoder"
          autoload :Encoder, "omnizip/formats/rar/compression/ppmd/encoder"
        end

        module LZ77Huffman
          autoload :SlidingWindow,
                   "omnizip/formats/rar/compression/lz77_huffman/sliding_window"
          autoload :HuffmanCoder,
                   "omnizip/formats/rar/compression/lz77_huffman/huffman_coder"
          autoload :HuffmanBuilder,
                   "omnizip/formats/rar/compression/lz77_huffman/huffman_builder"
          autoload :MatchFinder,
                   "omnizip/formats/rar/compression/lz77_huffman/match_finder"
          autoload :Decoder,
                   "omnizip/formats/rar/compression/lz77_huffman/decoder"
          autoload :Encoder,
                   "omnizip/formats/rar/compression/lz77_huffman/encoder"
        end
      end

      class << self
        # Create a RAR archive, yielding the writer for entries.
        # RAR5 is the default; pass version: 4 for the RAR4 writer.
        # RAR5-only options (solid, multi-volume, password, recovery)
        # are ignored for RAR4 — its writer warns about the
        # unimplemented ones and raises for passwords.
        #
        # @param path [String] Output archive path
        # @param options [Hash] Writer options
        # @return [String, Array<String>] Path(s) of the created
        #   archive (a volume set returns every volume)
        def create(path, options = {})
          version = options.fetch(:version, 5)
          writer = if version == 4
                     Writer.new(path, options)
                   else
                     Rar5::Writer.new(path, rar5_options(options))
                   end
          yield writer if block_given?
          writer.write
        end

        # Check if RAR extraction is available
        #
        # @return [Boolean] true if unrar available
        def available?
          Decompressor.available?
        end

        # Get decompressor information
        #
        # @return [Hash] Decompressor type and version
        def decompressor_info
          Decompressor.info
        end

        # Verify archive integrity
        #
        # @param archive_path [String] Path to RAR archive
        # @return [ArchiveVerifier::VerificationResult] Verification result
        def verify(archive_path, use_recovery: true)
          ArchiveVerifier.new(archive_path).verify(use_recovery: use_recovery)
        end

        # Repair corrupted archive
        #
        # @param archive_path [String] Path to corrupted RAR archive
        # @param output_path [String] Path for repaired archive
        # @return [ArchiveRepairer::RepairResult] Repair result
        def repair(archive_path, output_path)
          ArchiveRepairer.new.repair(archive_path, output_path)
        end

        private

        # Writer keywords the RAR5 writer understands
        def rar5_options(options)
          options.slice(:compression, :level, :solid, :multi_volume,
                        :volume_size, :volume_naming, :password,
                        :kdf_iterations, :recovery, :recovery_percent,
                        :include_mtime, :include_crc32, :dict_size)
        end
      end
    end
  end
end
