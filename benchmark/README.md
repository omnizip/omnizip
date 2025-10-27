# Omnizip Benchmark Suite

Comprehensive benchmark suite comparing omnizip performance against native
7-Zip.

## Purpose

This benchmark suite provides:

* Performance comparison between omnizip (Ruby) and 7-Zip (C)
* Compression ratio analysis for each algorithm
* Filter effectiveness measurements
* Baseline for future optimization work

## Requirements

* Ruby 2.7 or higher
* 7-Zip CLI tool (`7z` or `7za`) installed (optional but recommended)
* Omnizip gem dependencies installed (`bundle install`)

## Installation

Install 7-Zip for comparisons:

```bash
# macOS
brew install p7zip

# Ubuntu/Debian
sudo apt-get install p7zip-full

# Windows
# Download from https://www.7-zip.org/
```

## Running Benchmarks

### Quick Start

Run all benchmarks:

```bash
ruby benchmark/run_benchmarks.rb
```

Run quick benchmarks (1 size, 1 data type):

```bash
ruby benchmark/run_benchmarks.rb --quick
```

### Options

* `-v`, `--verbose` - Enable verbose output
* `-q`, `--quick` - Run quick benchmarks (faster, less coverage)
* `--compression-only` - Run only compression algorithm benchmarks
* `--filters-only` - Run only filter benchmarks
* `--output=FILE` - Save results to JSON file
* `-h`, `--help` - Show help message

### Examples

```bash
# Verbose output with JSON results
ruby benchmark/run_benchmarks.rb --verbose --output=results.json

# Quick compression-only benchmark
ruby benchmark/run_benchmarks.rb --quick --compression-only

# Full benchmark with results saved
ruby benchmark/run_benchmarks.rb --output=benchmark/results/full.json
```

## What Gets Benchmarked

### Compression Algorithms

* **LZMA** - Lempel-Ziv-Markov chain algorithm
* **LZMA2** - Improved LZMA with better multithreading
* **PPMd7** - Prediction by partial matching
* **BZip2** - Burrows-Wheeler transform compression

### Filters

* **BCJ x86** - Branch/Call/Jump filter for x86 executables
* **Delta** - Delta encoding for gradual data

### Data Types

* **Text** - Lorem ipsum text data
* **Source Code** - Ruby source code
* **Repetitive** - Highly compressible repetitive patterns
* **Random** - Incompressible random data

### Test Sizes

* 1KB (1,024 bytes)
* 10KB (10,240 bytes)
* 100KB (102,400 bytes)

## Interpreting Results

### Compression Ratio

```
Compression Ratio = Original Size / Compressed Size
```

Higher is better. Example: 3.0x means data compressed to 1/3 original size.

### Size Difference

Shows how much larger/smaller omnizip output is compared to 7-Zip:

* Positive % = omnizip produces larger files
* Negative % = omnizip produces smaller files (better)

Expect omnizip to be within 10-20% of 7-Zip size.

### Speed Ratio

```
Speed Ratio = Omnizip Time / 7-Zip Time
```

Shows how many times slower omnizip is compared to 7-Zip.

* Expected: 5-20x slower (Ruby vs C is normal)
* < 10x = Good performance for Ruby implementation
* > 20x = May need optimization

## Expected Performance Characteristics

### Compression Ratios

Omnizip should achieve similar compression ratios to 7-Zip (within 10-20%)
because both implement the same algorithms. Differences come from:

* Parameter tuning differences
* Implementation details
* Ruby vs C precision differences

### Speed

Ruby implementations are typically 5-20x slower than C implementations:

* **5-10x slower** = Excellent for Ruby
* **10-15x slower** = Good for Ruby
* **15-20x slower** = Acceptable for Ruby
* **> 20x slower** = May indicate optimization opportunities

### Algorithm-Specific Notes

* **LZMA/LZMA2**: Most complex, expect larger speed differences
* **BZip2**: Simpler algorithm, may have better speed ratios
* **PPMd7**: Memory-intensive, speed depends on implementation details

## Architecture

The benchmark suite follows object-oriented architecture:

```
benchmark/
├── models/              # Data models
│   ├── benchmark_result.rb      # Single benchmark result
│   └── comparison_result.rb     # Omnizip vs 7-Zip comparison
├── test_data.rb                 # Test data generator
├── compression_bench.rb         # Algorithm benchmarks
├── filter_bench.rb              # Filter benchmarks
├── benchmark_suite.rb           # Main orchestrator
├── reporter.rb                  # Results formatting
└── run_benchmarks.rb            # Executable runner
```

## Output Format

### Console Output

```
================================================================================
OMNIZIP vs 7-ZIP BENCHMARK RESULTS
================================================================================

--------------------------------------------------------------------------------
Test: lzma_text
--------------------------------------------------------------------------------
Metric                         Omnizip           7-Zip
--------------------------------------------------------------------------------
Input Size                       10.0KB           10.0KB
Compressed Size                   3.5KB            3.2KB
Compression Ratio                 2.86             3.13
Compression Time                2.500s           0.150s

--------------------------------------------------------------------------------
Comparison:
--------------------------------------------------------------------------------
  Size difference: +300 bytes (+9.4%)
  Speed ratio: 16.7x slower
```

### JSON Output

```json
{
  "timestamp": "2025-10-26T12:00:00Z",
  "results": [
    {
      "test_name": "lzma_text",
      "omnizip": {
        "algorithm": "lzma",
        "input_size": 10240,
        "compressed_size": 3584,
        "compression_ratio": 2.86,
        "compression_time": 2.5
      },
      "seven_zip": { ... },
      "comparison": {
        "size_difference_bytes": 300,
        "size_difference_percentage": 9.4,
        "compression_speed_ratio": 16.7
      }
    }
  ]
}
```

## Troubleshooting

### 7-Zip Not Found

If 7-Zip is not installed, benchmarks will still run but comparisons will show
"7-Zip not available". Install 7-Zip for full comparisons.

### Slow Benchmarks

Use `--quick` flag for faster results with less coverage, or run specific
benchmark types with `--compression-only` or `--filters-only`.

### Memory Issues

Large test files (100KB+) with complex algorithms may use significant memory.
Reduce test sizes in `benchmark_suite.rb` if needed.

## Future Enhancements

* Add decompression benchmarks
* Test larger file sizes (1MB, 10MB)
* Add multi-threaded benchmarks
* Compare memory usage
* Add visualization/charts

## Contributing

When adding new benchmarks:

1. Follow object-oriented design patterns
2. Use model classes for data representation
3. Maintain separation of concerns
4. Add documentation for new features
5. Run `bundle exec rubocop` before committing