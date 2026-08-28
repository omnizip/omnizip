# frozen_string_literal: true

module Omnizip
  module Archive
    # Block argument of +Archive.create+. Translates the documented
    # +add_file+/+add_directory+/+add_data+ vocabulary onto the
    # handler proxy's +add(name, source_path)+ / +add_data+ calls.
    class Builder
      def initialize(proxy)
        @proxy = proxy
      end

      # Add a file from disk, optionally under a different archive
      # path: +add_file('report.pdf', 'reports/report.pdf')+.
      def add_file(file_path, archive_path = nil)
        @proxy.add(archive_path || ::File.basename(file_path), file_path)
      end

      # Add a directory tree under its own name:
      # +add_directory('photos/')+ stores +photos/x.jpg+.
      def add_directory(dir_path)
        prefix = ::File.basename(::File.expand_path(dir_path))
        @proxy.add("#{prefix}/")
        walk(dir_path, prefix)
      end

      # Add in-memory content at +archive_path+.
      def add_data(archive_path, data)
        @proxy.add_data(archive_path, data)
      end

      private

      def walk(dir, prefix)
        ::Dir.children(dir).sort.each do |child|
          full = ::File.join(dir, child)
          name = "#{prefix}/#{child}"
          if ::File.directory?(full)
            @proxy.add("#{name}/")
            walk(full, name)
          else
            @proxy.add(name, full)
          end
        end
      end
    end
  end
end
