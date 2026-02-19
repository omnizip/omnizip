# Multi-Volume Archive Architecture

## Overview

The multi-volume archive feature enables splitting large RAR5 archives into multiple smaller volume files. This is essential for distributing large datasets across size-constrained media or network uploads.

## Key Components

### 1. VolumeOptions Model
**File**: [`models/volume_options.rb`](../models/volume_options.rb)

**Purpose**: Configuration for multi-volume archives using Lutaml::Model

**Attributes**:
- `max_volume_size` (Integer): Maximum size per volume in bytes (default: 100 MB)
- `volume_naming` (String): Naming pattern - "part", "volume", or "numeric"

**Key Methods**:
- `validate!`: Ensures volume size >= 64 KB minimum
- `parse_size(str)`: Converts "10M", "1G" to bytes

### 2. VolumeSplitter
**File**: [`volume_splitter.rb`](volume_splitter.rb)

**Purpose**: Handles data splitting logic and file distribution calculation

**Responsibilities**:
- Calculate optimal file distribution across volumes
- Track volume boundaries and remaining space
- Ensure atomic file placement (no mid-file splits in v0.5.0)
- Reserve header overhead (1 KB per volume)

**Key Methods**:
- `can_fit_in_current_volume?(size)`: Check space availability
- `calculate_file_distribution(files)`: Optimize file placement
- `needs_splitting?(total, max)`: Determine if splitting required

**Algorithm**:
```
For each file:
  If file fits in current volume with headers:
    Add to current volume
  Else:
    Finalize current volume
    Start new volume with this file
Return: Array of volume assignments
```

### 3. VolumeWriter
**File**: [`volume_writer.rb`](volume_writer.rb)

**Purpose**: Write individual .rar volume files with proper headers

**Responsibilities**:
- Write RAR5 signature to each volume
- Add volume-specific Main header flags
- Write file entries
- Add End header with continuation flags

**RAR5 Volume Flags**:
```ruby
# Main header
VOLUME_ARCHIVE_FLAG = 0x0001  # Indicates multi-volume archive
VOLUME_NUMBER_FLAG  = 0x0002  # Volume number in extra area

# End header
VOLUME_END_FLAG = 0x0001  # More volumes follow (not last)
```

**Volume Naming**:
- **part**: `archive.part1.rar`, `archive.part2.rar`, ... (default)
- **volume**: `archive.vol1.rar`, `archive.vol2.rar`, ...
- **numeric**: `archive.rar`, `archive.r00`, `archive.r01`, ...

### 4. VolumeManager
**File**: [`volume_manager.rb`](volume_manager.rb)

**Purpose**: Coordinate entire multi-volume archive creation

**Responsibilities**:
- Accept file additions
- Compress all files upfront
- Calculate optimal volume distribution
- Delegate to VolumeWriter for each volume
- Return array of created volume paths

**Workflow**:
```
1. User adds files via add_file() or add_directory()
2. User calls create_volumes()
3. Manager compresses all files
4. Calculate file distribution across volumes
5. For each volume:
   a. Create VolumeWriter
   b. Write signature + main header
   c. Write assigned file entries
   d. Write end header
6. Return volume paths
```

## Integration with Existing Writer

The [`Writer`](../writer.rb) class is enhanced with multi-volume support:

**New Options**:
- `multi_volume: true` - Enable multi-volume mode
- `volume_size: Integer` - Maximum volume size (accepts human-readable)

**API**:
```ruby
# Single archive (existing)
writer = Writer.new('archive.rar', compression: :lzma)
writer.add_file('file.txt')
writer.write

# Multi-volume (new)
writer = Writer.new('archive.rar',
  multi_volume: true,
  volume_size: '10M',  # or 10_485_760
  compression: :lzma
)
writer.add_file('largefile.dat')
writer.write  # Returns: ['archive.part1.rar', 'archive.part2.rar', ...]
```

**Implementation Strategy**:
- Check `multi_volume` option in `write()`
- If enabled, delegate to VolumeManager
- If disabled, use existing single-file logic
- Clean separation - no complex conditionals

## Data Flow

### Single Archive (Existing)
```
Files → Writer → Compress → Single .rar file
```

### Multi-Volume Archive (New)
```
Files → Writer (multi_volume=true)
         ↓
      VolumeManager
         ↓
      Compress all files
         ↓
      VolumeSplitter (calculate distribution)
         ↓
      For each volume:
        VolumeWriter → part1.rar, part2.rar, ...
```

## Volume Format Specification

### Volume File Structure
```
Volume 1 (archive.part1.rar):
  [RAR5 Signature: 8 bytes]
  [Main Header: VOLUME_ARCHIVE_FLAG set]
  [File1 Header + Data]
  [File2 Header + Data]
  ...
  [End Header: VOLUME_END_FLAG set]

Volume 2 (archive.part2.rar):
  [RAR5 Signature: 8 bytes]
  [Main Header: VOLUME_ARCHIVE_FLAG + VOLUME_NUMBER_FLAG]
  [File5 Header + Data]
  ...
  [End Header: VOLUME_END_FLAG set]

Last Volume (archive.partN.rar):
  [RAR5 Signature: 8 bytes]
  [Main Header: VOLUME_ARCHIVE_FLAG + VOLUME_NUMBER_FLAG]
  [FileX Header + Data]
  ...
  [End Header: VOLUME_END_FLAG NOT set]
```

## Limitations (v0.5.0)

1. **No File Spanning**: Individual files cannot span multiple volumes
   - Large files must fit in a single volume
   - Trade-off: Simplicity vs flexibility
   - Future: Implement file spanning in v0.6.0+

2. **Sequential Creation**: Volumes created sequentially, not in parallel
   - Simpler implementation
   - Future: Parallel volume writing with Ractors

3. **Fixed Boundaries**: Volume splits at file boundaries only
   - Predictable behavior
   - May result in inefficient space usage

## Testing Strategy

### Unit Tests
- VolumeOptions: Validation, size parsing
- VolumeSplitter: Distribution algorithm, space calculation
- VolumeWriter: Header generation, filename creation
- VolumeManager: File preparation, volume coordination

### Integration Tests
- Small archive (< volume size): Single volume
- Large archive (> volume size): Multiple volumes
- Many small files: Optimal distribution
- Few large files: One per volume
- Round-trip: Extract with unrar, verify integrity

### Compatibility Tests
- Extract with official unrar
- Extract with 7-Zip
- Verify all volume flags correct
- Verify volume sequence correct

## Performance Considerations

### Memory Usage
- All files compressed before splitting → Memory = sum of compressed sizes
- For 100 MB archives, reasonable memory footprint
- Future: Streaming compression for > 1 GB archives

### Disk I/O
- Sequential writes to multiple files
- No random access required
- Single pass through data

### Optimization Opportunities
1. Parallel compression of files (Ractors)
2. Streaming compression to reduce memory
3. Intelligent file ordering (similar files together for solid compression)

## Error Handling

### Volume Size Too Small
```ruby
VolumeOptions#validate!
# Raises ArgumentError if < 64 KB
```

### File Too Large
```ruby
VolumeSplitter#calculate_file_distribution
# Places large file in dedicated volume
# Logs warning if file > max_volume_size
```

### Disk Space Exhausted
```ruby
VolumeWriter#write
# Standard Ruby File I/O exceptions propagate
# Partial volumes cleaned up on failure (future)
```

## Future Enhancements (Post-v0.5.0)

1. **File Spanning**: Split large files across volumes
2. **Parallel Processing**: Compress files in parallel
3. **Streaming Mode**: Compress directly to volumes
4. **Resume Support**: Continue interrupted volume creation
5. **Volume Verification**: CRC checks for each volume
6. **Automatic Recovery**: Generate PAR2 for each volume

## References

- RAR5 Format Specification: https://www.rarlab.com/technote.htm
- RAR Volume Format Details: Section 4.3
- Volume Header Flags: Section 3.1

## Design Decisions

### Why Upfront Compression?
**Decision**: Compress all files before splitting
**Rationale**: Need exact compressed size to calculate distribution
**Trade-off**: Higher memory usage vs accurate splitting

### Why Atomic Files?
**Decision**: No file spanning in v0.5.0
**Rationale**: Simpler implementation, faster delivery
**Trade-off**: Potential wasted space vs implementation complexity

### Why Sequential Writing?
**Decision**: Write volumes one at a time
**Rationale**: Simpler error handling, predictable behavior
**Trade-off**: Slower for very large archives vs complexity

### Why Lutaml::Model?
**Decision**: Use Lutaml::Model for VolumeOptions
**Rationale**: Consistent with project architecture, serialization support
**Benefit**: YAML/JSON configuration files for volume settings