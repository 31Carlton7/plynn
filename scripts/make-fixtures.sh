#!/bin/bash
set -euo pipefail
DIR="$(dirname "$0")/../Tests/PlynnSpikeKitTests/Fixtures"
mkdir -p "$DIR"
say -v Samantha --data-format=LEF32@16000 -o "$DIR/hello.wav" \
  "Hello world. This is a test of the Plynn dictation spike, recording a full sentence with punctuation."
say -v Samantha --data-format=LEF32@16000 -o "$DIR/short.wav" "Testing"
say -v Samantha --data-format=LEF32@16000 -o "$DIR/long.wav" \
  "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. \
How vexingly quick daft zebras jump. The five boxing wizards jump quickly. \
Sphinx of black quartz, judge my vow. Two driven jocks help fax my big quiz."
