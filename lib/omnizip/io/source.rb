# frozen_string_literal: true


require "omnizip"
module Omnizip
  module IO
    # Polymorphic adapter for "things we can read bytes from".
    #
    # Callers that previously did:
    #
    #     data = input.respond_to?(:read) ? input.read : File.binread(input)
    #
    # should now do:
    #
    #     data = Omnizip::IO::Source.for(input).read
    #
    # Adapters:
    # - +IO+/+StringIO+/+Tempfile+ → wrapped as-is
    # - +String+ → treated as a file path; read with +File.binread+
    #   unless the string contains no NUL bytes and does not exist on
    #   disk, in which case it is treated as literal data
    # - +Object+ responding to +:read+ → delegated to
    class Source
      # Build a Source wrapper appropriate for +input+.
      #
      # @param input [IO, StringIO, String, #read] the read target
      # @return [Source]
      def self.for(input)
        case input
        when ::IO, ::StringIO, ::Tempfile then new(input)
        when String then StringSource.new(input)
        else
          unless input.respond_to?(:read)
            raise ArgumentError,
                  "Cannot adapt #{input.inspect} to Omnizip::IO::Source"
          end

          new(input)
        end
      end

      def initialize(io)
        @io = io
      end

      # Delegate reading to the underlying IO-like object.
      def read(length = nil, outbuf = nil)
        if length.nil?
          @io.read
        elsif outbuf
          @io.read(length, outbuf)
        else
          @io.read(length)
        end
      end

      def close
        @io.close if @io.respond_to?(:close)
      end

      # String input adapter. Treats the value as a file path if it
      # exists on disk and contains no NUL bytes, otherwise as raw
      # bytes.
      class StringSource < Source
        def initialize(value)
          super(nil)
          @value = value
        end

        def read(_length = nil, _outbuf = nil)
          if file_path?
            File.binread(@value)
          else
            @value.b
          end
        end

        def close; end

        private

        def file_path?
          !@value.include?("\0") && File.exist?(@value)
        end
      end
    end

    # Polymorphic adapter for "things we can write bytes to".
    #
    # Adapters:
    # - +IO+/+StringIO+/+Tempfile+ → wrapped as-is
    # - +String+ → treated as a file path; writes via +File.binwrite+
    # - +Object+ responding to +:write+ → delegated to
    class Sink
      def self.for(output)
        case output
        when ::IO, ::StringIO, ::Tempfile then new(output)
        when String then PathSink.new(output)
        else
          unless output.respond_to?(:write)
            raise ArgumentError,
                  "Cannot adapt #{output.inspect} to Omnizip::IO::Sink"
          end

          new(output)
        end
      end

      def initialize(io)
        @io = io
      end

      def write(data)
        @io.write(data)
      end

      def close
        @io.close if @io.respond_to?(:close)
      end

      # File-path sink: opens the file for binary write on #write and
      # closes after.
      class PathSink < Sink
        def initialize(path)
          super(nil)
          @path = path
          @file = nil
        end

        def write(data)
          File.binwrite(@path, data)
        end

        def close; end
      end
    end
  end
end
