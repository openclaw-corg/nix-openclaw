#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const storePath = process.argv[2];
if (!storePath) {
  console.error("usage: list-pnpm-store-integrities.js STORE_PATH");
  process.exit(2);
}

for (const entry of fs.readdirSync(storePath, { withFileTypes: true })) {
  if (!entry.isDirectory() || !/^v[0-9]+$/.test(entry.name)) continue;

  const dbPath = path.join(storePath, entry.name, "index.db");
  if (!fs.existsSync(dbPath)) continue;

  const db = new DatabaseSync(dbPath, { readOnly: true });
  for (const { key } of db.prepare("SELECT key FROM package_index").all()) {
    console.log(key.split("\t", 1)[0]);
  }
  db.close();
}
