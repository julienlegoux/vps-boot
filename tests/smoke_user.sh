#!/usr/bin/env bash
# Run inside the disposable toolchain container as its unprivileged test user.
set -euo pipefail
cd "$HOME"
python -c 'import sys; print(sys.prefix); assert sys.prefix != sys.base_prefix'
python -m pip --version
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
python -m venv "$work/venv"
"$work/venv/bin/python" -c 'import ssl, sqlite3; print("Python venv works")'
printf 'fn main() { println!("Rust works"); }\n' > "$work/main.rs"
rustc "$work/main.rs" -o "$work/rust-smoke"
"$work/rust-smoke"
cargo new --quiet --vcs none "$work/rust-project"
cargo build --quiet --manifest-path "$work/rust-project/Cargo.toml"
printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("Go works") }\n' > "$work/main.go"
go run "$work/main.go"
printf 'class Smoke { public static void main(String[] args) { System.out.println("Java works"); } }\n' > "$work/Smoke.java"
javac "$work/Smoke.java"
java -cp "$work" Smoke
node -e 'console.log("Node works")'
for tool in bun pnpm claude opencode codex gemini pi vercel neonctl herdr; do
  "$tool" --version
done
hostinger version
