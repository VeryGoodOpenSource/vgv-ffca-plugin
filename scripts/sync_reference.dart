// Regenerates references/ffca_architecture.md from the canonical Notion page.
//
// Source of truth:
//   https://www.notion.so/verygoodventures/Feature-First-Clean-Architecture-2fb45eb3279580568023d1cf9bc00c24
//
// TODO: implement the sync. The intended flow is to take a Notion export of the
// FFCA architecture page and regenerate references/ffca_architecture.md from it,
// so the in-plugin mirror never drifts from the source. A CI check (or scheduled
// workflow) then flags when the committed copy is stale. The provided
// references/ffca_architecture.md is current as of today and maintained by hand
// until this automation lands.

import 'dart:io';

void main() {
  stderr.writeln(
    'sync_reference.dart is not implemented yet. references/ffca_architecture.md '
    'is currently maintained by hand from the Notion page. See the TODO at the '
    'top of this file.',
  );
  exit(64);
}
