#!/usr/bin/env sh

echo "-- Compiling liteipc_native… This might take a while."
pushd liteipc
cargo build --release
popd

echo "-- Symlinking to the current directory"
ln -s $PWD/liteipc/target/release/libliteipc.so $PWD/liteipc_native.so

echo "-- liteipc is now installed!"
echo "-- Follow the README for further instructions."
