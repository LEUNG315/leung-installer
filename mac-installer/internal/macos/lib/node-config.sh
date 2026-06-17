#!/usr/bin/env bash
# LEUNG CLI Installer - Centralized Node.js release configuration

NODE_LTS_MAJOR="${NODE_LTS_MAJOR:-24}"
NODE_LTS_VERSION="${NODE_LTS_VERSION:-24.16.0}"
NODE_LTS_SHA256_DARWIN_X64="${NODE_LTS_SHA256_DARWIN_X64:-298b4c7b3cb80765c8703e42b90324a4ece3b6634947b89e769c3c980ab55185}"
NODE_LTS_SHA256_DARWIN_ARM64="${NODE_LTS_SHA256_DARWIN_ARM64:-39189dab4eeb15706c424af0ac08a3044c9e48f7db12a7d77f6b7aafc7dd5df6}"

NODE_RELEASE_BASES_DEFAULT=(
    "https://nodejs.org/dist"
    "https://mirrors.cloud.tencent.com/nodejs-release"
)
