# Upstream attribution and modifications

Source: https://github.com/huggingface/swift-transformers
Version: 1.3.5
Revision: 48473106a93b2d8dfb114b82f0628ebbb71734e7
License: Apache-2.0, original license in LICENSE.

This directory contains the unmodified Hub and Tokenizers sources and their
resources, except for the explicitly marked resource lookup change in
Sources/Hub/Hub.swift. That change prefers the resource bundle in a native
macOS app's Contents/Resources directory before SwiftPM's generated lookup.
The Package.swift is reduced to those two products and their original dependencies.
The engine and RUAccent consume these products through a root local dependency
with the same package identity. This makes the fix reproducible and keeps signed
app bundles independent of absolute developer build paths.
