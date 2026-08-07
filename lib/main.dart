import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Nothing async: the database opens lazily on first read, so the first frame
  // never waits on I/O.
  runApp(const ProviderScope(child: KoriApp()));
}
