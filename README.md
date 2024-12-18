# RebelDB™

A new database engine is brewing 🧪, imagine if REBOL and SQLite had a rebellious offspring ⚡️

## Overview

RebelDB™ is a high-performance database engine written in Zig that combines efficient memory management with flexible storage options. Key features:

- Variable-length integer encoding optimized for lexicographical ordering
- Flexible page-based storage system with configurable alignment
- Zero-copy value storage with efficient memory management
- Compile-time configuration for optimal performance

## Quick Start

```zig
const std = @import("std");
const Page = @import("page.zig").Page;
const ByteAligned = @import("page.zig").ByteAligned;
const Static = @import("page.zig").Static;
const Mutable = @import("page.zig").Mutable;

// Create a simple page with 128 bytes capacity
var data: [128]u8 = undefined;
const BasicPage = Page(u8, Static(128), ByteAligned(u8), Mutable(u8));
var page: *BasicPage = @ptrCast(&data);

// Initialize and store values
_ = page.init(128);
const val = page.alloc(16);
@memcpy(val, "Hello, RebelDB!");
```

## Documentation

- [Architecture Overview](docs/architecture.md)
- Examples:
  - [Basic Usage](docs/examples/basic_usage.zig)
  - [Page Configurations](docs/examples/page_configuration.zig)
  - [Memory Management](docs/examples/memory_management.zig)

## About Huly.io

RebelDB™ can be an essential part of next generation [Huly.io](https://huly.io). Huly is [open-source](https://github.com/hcengineering) product
for process management, knowledge management, and team collaboration. It's crafted to be an all-in-one solution,
enabling teams to manage their work more efficiently and serving as an alternative to tools like Jira, Linear, Asana, Slack, Notion, Motion, and Roam.

<sup>© 2024 [Huly Labs](https://hulylabs.com) • All Rights Reserved</sup>
