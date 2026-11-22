import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pano_360_pro/app.dart';

void main() {
  testWidgets('PANO app boots', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PanoApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('PANO'), findsWidgets);
  });
}
