# RebelDB™ Architecture Documentation

## Overview

RebelDB™ is a modern database engine implemented in Zig, focusing on efficient memory management, flexible data storage, and optimized encoding strategies. This document outlines the core architectural components and design decisions that shape the system.

## System Components

### Core Components Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                      RebelDB Engine                         │
├───────────────┬───────────────┬──────────────┬─────────────┤
│   Page        │    Value      │    Memory    │   Encoding  │
│  Management   │   Storage     │  Management  │   System    │
├───────────────┼───────────────┼──────────────┼─────────────┤
│ - ByteAligned │ - Int        │ - HeapAlloc  │ - VarInt    │
│ - NibbleAlign │ - Str        │ - PageAlloc  │ - LexOrder  │
│ - Static/Dyn  │ - Blob       │ - MemFile    │ - Efficient │
└───────────────┴───────────────┴──────────────┴─────────────┘
```

### Component Details

1. Page Management
   - Flexible page configurations
   - Alignment strategies (Byte/Nibble)
   - Capacity options (Static/Dynamic)
   - Mutability control (Readonly/Mutable)

2. Value Storage
   - Integer representation
   - String handling
   - Blob storage
   - Block management

3. Memory Management
   - Heap allocation
   - Page allocation
   - Memory file handling
   - Resource cleanup

4. Encoding System
   - Variable-length integers
   - Lexicographical ordering
   - Efficient space usage
   - Performance optimization

## Memory Layout

### Page Structure
```
┌──────────────┬─────────────────────┬─────────────────┐
│   Header     │    Values           │     Indices     │
│              │    (Growing →)      │    (← Growing)  │
└──────────────┴─────────────────────┴─────────────────┘
```

### Page Components
1. Header
   - Page metadata
   - Configuration information
   - Capacity details

2. Values Section
   - Grows forward from header
   - Variable-length entries
   - Aligned storage

3. Indices Section
   - Grows backward from end
   - Fixed-size entries
   - Alignment-specific format

## Type System

### Core Types

1. Object (packed union)
```zig
pub const Object = packed union {
    val: Value,
    addr: packed struct { index: Index, page: PageId }
};
```

2. Page Configuration
```zig
Page(IndexType, Capacity, Indices, Mutability)
```
- IndexType: Type used for indexing
- Capacity: Static or Dynamic
- Indices: ByteAligned or NibbleAligned
- Mutability: Readonly or Mutable

3. Value Types
- Integers (variable-length encoded)
- Strings (length-prefixed)
- Blobs (binary data)
- Blocks (structured data)

## Design Decisions

### 1. Page-Based Storage

**Decision**: Implement a page-based storage system with flexible configuration options.

**Rationale**:
- Efficient memory management
- Configurable alignment for different use cases
- Balance between flexibility and performance
- Support for various data types and sizes

### 2. Variable-Length Encoding

**Decision**: Use a custom variable-length integer encoding scheme.

**Rationale**:
- Space efficiency for different value ranges
- Preserved lexicographical ordering
- Optimized performance for common cases
- Flexible storage requirements

### 3. Bidirectional Page Growth

**Decision**: Implement values growing forward and indices growing backward within pages.

**Rationale**:
- Efficient space utilization
- Reduced fragmentation
- Simple allocation strategy
- Clear separation of concerns

### 4. Type System Design

**Decision**: Use Zig's compile-time features for configuration.

**Rationale**:
- Type safety at compile time
- Flexible configuration options
- Performance optimization
- Clear interface boundaries

## Performance Considerations

### Memory Management
- Page reuse strategies
- Efficient allocation patterns
- Minimal fragmentation
- Resource cleanup

### Encoding Optimization
- Fast encoding/decoding
- Space efficiency
- Sort order preservation
- Cache-friendly access

### Page Configuration
- Alignment options for different needs
- Static vs Dynamic trade-offs
- Mutability control
- Index optimization

## Future Considerations

### Potential Enhancements
1. Concurrent access patterns
2. Advanced caching strategies
3. Extended type support
4. Enhanced error handling

### Optimization Opportunities
1. Page allocation strategies
2. Encoding improvements
3. Memory layout optimization
4. Index structure refinements
