# frozen_string_literal: true

require "fileutils"

module Benchmark
  # Generates test data files for benchmarking compression algorithms
  class TestData
    LOREM_IPSUM = <<~TEXT
      Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
      eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
      enim ad minim veniam, quis nostrud exercitation ullamco laboris
      nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor
      in reprehenderit in voluptate velit esse cillum dolore eu fugiat
      nulla pariatur. Excepteur sint occaecat cupidatat non proident,
      sunt in culpa qui officia deserunt mollit anim id est laborum.
    TEXT

    attr_reader :data_dir

    def initialize(data_dir = "benchmark/data")
      @data_dir = data_dir
      FileUtils.mkdir_p(@data_dir)
    end

    def generate_text(size, filename: "text.txt")
      path = File.join(data_dir, filename)
      content = generate_lorem_text(size)
      File.binwrite(path, content)
      path
    end

    def generate_source_code(size, filename: "source.rb")
      path = File.join(data_dir, filename)
      content = generate_ruby_source(size)
      File.binwrite(path, content)
      path
    end

    def generate_repetitive(size, filename: "repetitive.bin")
      path = File.join(data_dir, filename)
      pattern = "ABCDEFGH" * 32
      content = (pattern * ((size / pattern.bytesize) + 1))[0, size]
      File.binwrite(path, content)
      path
    end

    def generate_random(size, filename: "random.bin")
      path = File.join(data_dir, filename)
      content = Random.bytes(size)
      File.binwrite(path, content)
      path
    end

    def generate_multimedia(size, filename: "multimedia.bin")
      path = File.join(data_dir, filename)
      content = generate_gradient_data(size)
      File.binwrite(path, content)
      path
    end

    def cleanup
      FileUtils.rm_rf(data_dir)
      FileUtils.mkdir_p(data_dir)
    end

    private

    def generate_lorem_text(size)
      paragraphs = []
      current_size = 0

      while current_size < size
        paragraphs << LOREM_IPSUM
        current_size += LOREM_IPSUM.bytesize
      end

      paragraphs.join("\n\n")[0, size]
    end

    def generate_ruby_source(size)
      code = <<~RUBY
        # frozen_string_literal: true

        module Example
          class DataProcessor
            attr_reader :data

            def initialize(data)
              @data = data
            end

            def process
              data.map { |item| transform(item) }
            end

            def transform(item)
              item.upcase.reverse
            end

            def filter(predicate)
              data.select { |item| predicate.call(item) }
            end

            def aggregate
              data.inject(0) { |sum, item| sum + item.length }
            end
          end
        end
      RUBY

      lines = []
      current_size = 0

      counter = 0
      while current_size < size
        lines << code
        counter += 1
        lines << "\n# Generated code block #{counter}\n"
        current_size = lines.join.bytesize
      end

      lines.join[0, size]
    end

    def generate_gradient_data(size)
      data = []
      step = 256.0 / [size, 256].min

      size.times do |i|
        value = ((i * step) % 256).to_i
        data << value.chr
      end

      data.join
    end
  end
end
